import '../cube/cubie_cube.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';

/// One decoded event from a GoCube notification.
sealed class GoCubeEvent {}

/// A full cube state. [isResync] is `true` when it corrected a model that was
/// already anchored — i.e. moves were lost (GoCube carries no move counter, so
/// drift is only ever caught by a state message, not per packet), and anything
/// holding a baseline from before must retake it.
class GoCubeStateEvent extends GoCubeEvent {
  final CubeState state;
  final bool isResync;
  GoCubeStateEvent(this.state, {this.isResync = false});
}

/// A single quarter turn plus the resulting full state.
class GoCubeMoveEvent extends GoCubeEvent {
  final CubeMove move;
  final CubeState stateAfter;
  GoCubeMoveEvent(this.move, this.stateAfter);
}

class GoCubeBatteryEvent extends GoCubeEvent {
  final int level;
  GoCubeBatteryEvent(this.level);
}

/// Pure decoder + protocol parser for GoCube / Rubik's Connected (a GoCube
/// rebadge), ported from csTimer `gocube.js` (GPL-3.0). No BLE/Flutter
/// dependencies — feed it raw notification bytes and it emits [GoCubeEvent]s
/// while tracking full cube state. GoCube is **unencrypted**: no MAC, no cipher.
class GoCubeParser {
  /// Frame markers: every packet is `2a · len · type · data… · crc · 0d · 0a`.
  static const int _prefix = 0x2a;
  static const int _cr = 0x0d;
  static const int _lf = 0x0a;

  /// Message types the cube sends (byte 2). Type 3 (quaternion/orientation) is
  /// received but not decoded — the trainer has no use for orientation.
  static const int msgMove = 1;
  static const int msgState = 2;
  static const int msgBattery = 5;

  /// Request opcodes written to the cube. GoCube expects these as a single raw
  /// byte with no framing.
  static const int reqBattery = 50;
  static const int reqState = 51;

  /// csTimer's mapping tables. [_axisPerm] turns the cube's own face index into
  /// an index in `"URFDLB"`; the state decode reads each face's 8 perimeter
  /// stickers through [_facePerm] rotated by [_faceOffset], with colours coded
  /// in the `"BFUDRL"` scheme.
  static const List<int> _axisPerm = [5, 2, 0, 3, 1, 4];
  static const List<int> _facePerm = [0, 1, 2, 5, 8, 7, 6, 3];
  static const List<int> _faceOffset = [0, 0, 6, 2, 0, 0];
  static const String _colours = 'BFUDRL';
  static const List<Face> _faceByUrfdlb = [
    Face.U, Face.R, Face.F, Face.D, Face.L, Face.B, //
  ];

  final CubieCube _cube = CubieCube();
  int _batteryLevel = 0;
  bool _anchored = false;
  int? _baseHostMs;

  int get batteryLevel => _batteryLevel;

  CubeState get currentState => CubeState(_cube.toFaceCube());

  /// `true` until the first state message anchors the model. Moves are dropped
  /// while unanchored — integrating them from a guessed solved cube would be
  /// silently wrong.
  bool get needsAnchor => !_anchored;

  List<int> encodeRequestState() => const [reqState];
  List<int> encodeRequestBattery() => const [reqBattery];

  /// Realign the tracked model to [state] without a physical resync.
  void setState(CubeState state) {
    if (_cube.fromFacelet(state.facelets)) _anchored = true;
  }

  List<GoCubeEvent> parse(List<int> raw, int hostTimeMs) {
    if (raw.length < 6) return const [];
    if (raw[0] != _prefix ||
        raw[raw.length - 2] != _cr ||
        raw[raw.length - 1] != _lf) {
      return const [];
    }
    final msgLen = raw.length - 6; // strip prefix+len+type and crc+cr+lf
    switch (raw[2]) {
      case msgMove:
        return _parseMoves(raw, msgLen, hostTimeMs);
      case msgState:
        return _parseState(raw, msgLen);
      case msgBattery:
        if (msgLen < 1) return const [];
        _batteryLevel = raw[3];
        return [GoCubeBatteryEvent(_batteryLevel)];
      default:
        return const [];
    }
  }

  List<GoCubeEvent> _parseMoves(List<int> raw, int msgLen, int hostTimeMs) {
    if (!_anchored) return const [];
    _baseHostMs ??= hostTimeMs;
    // Each move is 2 bytes; only the first (face + direction) is meaningful —
    // the second is a turn duration csTimer discards, so GoCube gives no usable
    // per-move cube clock and timestamps ride host time.
    final count = msgLen ~/ 2;
    final events = <GoCubeEvent>[];
    for (var k = 0; k < count; k++) {
      final b = raw[3 + k * 2];
      final code = b >> 1;
      if (code > 5) return events; // corrupt byte — keep the valid moves, stop
      final face = _faceByUrfdlb[_axisPerm[code]];
      final prime = (b & 1) == 1;
      _cube.applyMove(face, prime);
      events.add(GoCubeMoveEvent(
        CubeMove(
          face: face,
          prime: prime,
          cubeTimestamp: Duration(milliseconds: hostTimeMs - _baseHostMs!),
          hostTimestamp: k == count - 1
              ? DateTime.fromMillisecondsSinceEpoch(hostTimeMs)
              : null,
        ),
        CubeState(_cube.toFaceCube()),
      ));
    }
    return events;
  }

  List<GoCubeEvent> _parseState(List<int> raw, int msgLen) {
    if (msgLen < 54) return const [];
    final f = List<String>.filled(54, '');
    for (var a = 0; a < 6; a++) {
      final base = _axisPerm[a] * 9;
      final aoff = _faceOffset[a];
      f[base + 4] = _colours[raw[3 + a * 9]];
      for (var i = 0; i < 8; i++) {
        f[base + _facePerm[(i + aoff) % 8]] = _colours[raw[3 + a * 9 + i + 1]];
      }
    }
    final before = _cube.clone();
    if (!_cube.fromFacelet(f.join())) return const []; // structurally invalid
    final wasAnchored = _anchored;
    _anchored = true;
    return [
      GoCubeStateEvent(CubeState(_cube.toFaceCube()),
          isResync: wasAnchored && _cube != before),
    ];
  }
}
