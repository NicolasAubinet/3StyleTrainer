import '../cube/cubie_cube.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';

/// One decoded event from a Giiker notification.
sealed class GiikerEvent {}

/// A full cube state. [isResync] is `true` when it corrected an anchored model
/// whose missed moves could not be recovered from the packet's move history —
/// anything holding a baseline from before must retake it.
class GiikerStateEvent extends GiikerEvent {
  final CubeState state;
  final bool isResync;
  GiikerStateEvent(this.state, {this.isResync = false});
}

/// A single quarter turn plus the resulting full state.
class GiikerMoveEvent extends GiikerEvent {
  final CubeMove move;
  final CubeState stateAfter;
  GiikerMoveEvent(this.move, this.stateAfter);
}

/// Pure decoder for Giiker / Xiaomi Mi Smart Magic Cube packets, ported from
/// csTimer `giikercube.js` (GPL-3.0). No BLE/Flutter dependencies.
///
/// Every 20-byte notification carries the **full cube state** (cubie nibbles in
/// Giiker's own piece ordering) plus the last four moves, newest first. The
/// state is authoritative; the move history only names what happened. A missed
/// notification is healed by replaying the shortest history suffix that takes
/// the tracked state to the packet state — only when no suffix fits does the
/// packet become a resync. Newer firmware "encrypts" with a fixed additive key,
/// flagged by byte 18 == 0xA7 (that byte is a move-face nibble pair on plain
/// packets, whose values never exceed 6 — the flag cannot collide).
class GiikerParser {
  static const int _encryptedMarker = 0xa7;

  /// Additive "encryption" key newer firmwares apply (see [_toNibbles]).
  static const List<int> decryptKey = [
    176, 81, 104, 224, 86, 137, 237, 119, 38, 26, 193, 161, //
    210, 126, 150, 81, 93, 13, 236, 249, 89, 235, 88, 24,
    113, 81, 214, 131, 130, 199, 2, 169, 39, 165, 171, 41,
  ];

  /// Giiker's corner/edge facelet tables — its piece ordering differs from the
  /// standard one in [CubieCube], so the state is decoded through these into a
  /// facelet string and re-parsed, exactly as csTimer does.
  static const List<List<int>> cFacelet = [
    [26, 15, 29],
    [20, 8, 9],
    [18, 38, 6],
    [24, 27, 44],
    [51, 35, 17],
    [45, 11, 2],
    [47, 0, 36],
    [53, 42, 33],
  ];

  static const List<List<int>> eFacelet = [
    [25, 28],
    [23, 12],
    [19, 7],
    [21, 41],
    [32, 16],
    [5, 10],
    [3, 37],
    [30, 43],
    [52, 34],
    [48, 14],
    [46, 1],
    [50, 39],
  ];

  /// Per-slot corner orientation sign: `ori = (3 + nibble * sign) % 3`.
  static const List<int> _coMask = [-1, 1, -1, 1, 1, -1, 1, -1];

  /// Move face nibble 1..6 in the cube's order.
  static const List<Face> _moveFaces = [
    Face.B, Face.D, Face.L, Face.U, Face.R, Face.F, //
  ];

  final CubieCube _cube = CubieCube();
  bool _anchored = false;
  int? _baseHostMs;

  CubeState get currentState => CubeState(_cube.toFaceCube());

  /// `true` until a first packet (notification or GATT read) anchors the model.
  bool get needsAnchor => !_anchored;

  /// Realign the tracked model to [state] without a physical resync.
  void setState(CubeState state) {
    if (_cube.fromFacelet(state.facelets)) _anchored = true;
  }

  List<GiikerEvent> parse(List<int> raw, int hostTimeMs) {
    final hex = _toNibbles(raw);
    if (hex == null) return const [];
    final packetCube = _decodeState(hex);
    if (packetCube == null) return const [];

    if (!_anchored) {
      _anchored = true;
      _cube.init(packetCube.ca, packetCube.ea);
      return [GiikerStateEvent(CubeState(_cube.toFaceCube()))];
    }
    if (packetCube == _cube) return const []; // duplicate notification

    final quarters = _recoverMoves(hex, packetCube);
    if (quarters == null) {
      _cube.init(packetCube.ca, packetCube.ea);
      return [GiikerStateEvent(CubeState(_cube.toFaceCube()), isResync: true)];
    }

    _baseHostMs ??= hostTimeMs;
    final events = <GiikerEvent>[];
    for (var i = 0; i < quarters.length; i++) {
      final (face, prime) = quarters[i];
      _cube.applyMove(face, prime);
      events.add(GiikerMoveEvent(
        CubeMove(
          face: face,
          prime: prime,
          cubeTimestamp: Duration(milliseconds: hostTimeMs - _baseHostMs!),
          hostTimestamp: i == quarters.length - 1
              ? DateTime.fromMillisecondsSinceEpoch(hostTimeMs)
              : null,
        ),
        CubeState(_cube.toFaceCube()),
      ));
    }
    return events;
  }

  /// First 20 bytes as 4-bit nibbles, decrypting when flagged. An encrypted
  /// packet decodes to 18 bytes / 36 nibbles (its history holds two moves, not
  /// four).
  static List<int>? _toNibbles(List<int> value) {
    if (value.length < 20) return null;
    var raw = value.sublist(0, 20);
    if (raw[18] == _encryptedMarker) {
      final k1 = raw[19] >> 4 & 0xf;
      final k2 = raw[19] & 0xf;
      raw = [
        for (var i = 0; i < 18; i++)
          (raw[i] + decryptKey[i + k1] + decryptKey[i + k2]) & 0xff,
      ];
    }
    return [
      for (final b in raw) ...[b >> 4 & 0xf, b & 0xf],
    ];
  }

  /// Cubie nibbles → a standard [CubieCube], or null on a corrupt packet.
  static CubieCube? _decodeState(List<int> hex) {
    final ca = List<int>.filled(8, 0);
    final ea = List<int>.filled(12, 0);
    for (var i = 0; i < 8; i++) {
      if (hex[i] < 1 || hex[i] > 8) return null;
      ca[i] = (hex[i] - 1) | ((3 + hex[i + 8] * _coMask[i]) % 3) << 3;
    }
    for (var i = 0; i < 12; i++) {
      if (hex[i + 16] < 1 || hex[i + 16] > 12) return null;
      final eo = (hex[28 + i ~/ 4] >> (3 - i % 4)) & 1;
      ea[i] = (hex[i + 16] - 1) << 1 | eo;
    }

    // Giiker piece ordering → facelet colours → standard ordering.
    final f = List<int>.generate(54, (i) => i);
    for (var c = 0; c < 8; c++) {
      final j = ca[c] & 7;
      final ori = ca[c] >> 3;
      for (var n = 0; n < 3; n++) {
        f[cFacelet[c][(n + ori) % 3]] = cFacelet[j][n];
      }
    }
    for (var e = 0; e < 12; e++) {
      final j = ea[e] >> 1;
      final ori = ea[e] & 1;
      for (var n = 0; n < 2; n++) {
        f[eFacelet[e][(n + ori) % 2]] = eFacelet[j][n];
      }
    }
    final facelets = f.map((i) => 'URFDLB'[i ~/ 9]).join();
    final cube = CubieCube();
    return cube.fromFacelet(facelets) ? cube : null;
  }

  /// The shortest suffix of the packet's move history (newest first, each entry
  /// one or two quarter turns) that takes the tracked state to [target], in
  /// execution order — or null when none fits.
  List<(Face, bool)>? _recoverMoves(List<int> hex, CubieCube target) {
    final history = <List<(Face, bool)>>[];
    for (var k = 0; 32 + k * 2 + 1 < hex.length; k++) {
      final entry = _decodeEntry(hex[32 + k * 2], hex[33 + k * 2]);
      if (entry == null) break;
      history.add(entry);
    }
    for (var k = 1; k <= history.length; k++) {
      final candidate = _cube.clone();
      final quarters = <(Face, bool)>[
        for (var i = k - 1; i >= 0; i--) ...history[i],
      ];
      for (final (face, prime) in quarters) {
        candidate.applyMove(face, prime);
      }
      if (candidate == target) return quarters;
    }
    return null;
  }

  /// One history entry as quarter turns: dir 1 = CW, 2 = double, 3 = CCW
  /// (csTimer's `" 2'".charAt((dir - 1) % 7)`).
  static List<(Face, bool)>? _decodeEntry(int faceNibble, int dirNibble) {
    if (faceNibble < 1 || faceNibble > 6) return null;
    final face = _moveFaces[faceNibble - 1];
    return switch ((dirNibble - 1) % 7) {
      0 => [(face, false)],
      1 => [(face, false), (face, false)],
      2 => [(face, true)],
      _ => null,
    };
  }
}
