import '../crypto/gan_cipher.dart';
import '../cube/cubie_cube.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';

/// One decoded event from the cube's notification stream.
sealed class MoyuEvent {}

/// The cube's initial full state (anchors move tracking).
class MoyuStateEvent extends MoyuEvent {
  final CubeState state;
  MoyuStateEvent(this.state);
}

/// A single move plus the resulting full cube state.
class MoyuMoveEvent extends MoyuEvent {
  final CubeMove move;
  final CubeState stateAfter;
  MoyuMoveEvent(this.move, this.stateAfter);
}

/// More moves happened than the last packet could carry, so the tracked model no
/// longer matches the cube. Moves are ignored until a fresh state re-anchors it.
class MoyuDesyncEvent extends MoyuEvent {
  /// Moves the cube reported that never reached the model.
  final int lostMoves;
  MoyuDesyncEvent(this.lostMoves);
}

class MoyuBatteryEvent extends MoyuEvent {
  final int level;
  MoyuBatteryEvent(this.level);
}

class MoyuInfoEvent extends MoyuEvent {
  final String deviceName;
  final String hardwareVersion;
  final String softwareVersion;
  MoyuInfoEvent(this.deviceName, this.hardwareVersion, this.softwareVersion);
}

/// Pure decoder + protocol parser for the MoYu WeiLong V10 AI (`WCU_MY32`),
/// ported from csTimer `moyu32cube.js` (GPL-3.0). No BLE/Flutter dependencies —
/// feed it decrypted-once-removed raw packets and it emits [MoyuEvent]s while
/// tracking full cube state.
class MoyuV10Parser {
  /// MoYu V10 base key/IV (LZString-decompressed from the driver's KEYS).
  static const List<int> baseKey = [21, 119, 58, 92, 103, 14, 45, 31, 23, 103, 42, 19, 155, 103, 82, 87];
  static const List<int> baseIv = [17, 35, 38, 37, 134, 42, 44, 59, 85, 6, 127, 49, 126, 103, 33, 87];

  /// Message opcodes for requests written to the cube.
  static const int opInfo = 161;
  static const int opStatus = 163;
  static const int opPower = 164;

  /// Move face codes index this order (`"FBUDLR"[code]`).
  static const List<Face> _faceByCode = [Face.F, Face.B, Face.U, Face.D, Face.L, Face.R];

  final GanCipher _cipher;
  final CubieCube _cube = CubieCube();

  int _prevMoveCnt = -1;
  int _moveCnt = -1;
  int _deviceTime = 0;
  int _deviceTimeOffset = 0;
  int? _batteryLevel;
  bool _pullPending = false;

  MoyuV10Parser(List<int> macBytes)
      : _cipher = GanCipher.forMac(baseKey, baseIv, macBytes);

  /// `null` until the cube has answered a power request.
  int? get batteryLevel => _batteryLevel;

  CubeState get currentState => CubeState(_cube.toFaceCube());

  /// `true` while the model is untrusted: moves are dropped until a state
  /// message re-anchors it (after a [MoyuDesyncEvent]).
  bool get needsAnchor => _prevMoveCnt == -1;

  /// Accept the next state message even though the model is anchored, so a
  /// voluntary pull re-anchors on the cube's own facelets. Unlike a desync this
  /// keeps tracking moves meanwhile, so none are lost while the pull is in
  /// flight.
  void requestPull() => _pullPending = true;

  /// Force the next state message to re-anchor (used after packet loss).
  void resetAnchor() => _prevMoveCnt = -1;

  /// Realign the tracked model to [state] without a physical resync.
  void setState(CubeState state) => _cube.fromFacelet(state.facelets);

  /// Build an encrypted request packet for [opcode].
  List<int> encodeRequest(int opcode) {
    final req = List<int>.filled(20, 0);
    req[0] = opcode;
    return _cipher.encode(req);
  }

  List<MoyuEvent> parse(List<int> raw, int hostTimeMs) {
    final data = _cipher.decode(raw);
    final bits = StringBuffer();
    for (final b in data) {
      bits.write(b.toRadixString(2).padLeft(8, '0'));
    }
    final s = bits.toString();
    int val(int start, int end) => int.parse(s.substring(start, end), radix: 2);

    switch (val(0, 8)) {
      case 161:
        final name = StringBuffer();
        for (var i = 0; i < 8; i++) {
          name.writeCharCode(val(8 + i * 8, 16 + i * 8));
        }
        final hw = '${val(72, 80)}.${val(80, 88)}';
        final sw = '${val(88, 96)}.${val(96, 104)}';
        return [MoyuInfoEvent(name.toString().trim(), hw, sw)];

      case 163:
        if (_prevMoveCnt != -1 && !_pullPending) return [];
        final facelet = _parseFacelet(s.substring(8, 152));
        // Garbage from a wrong key can pass for a state message, so only a
        // legal facelet is allowed to anchor. Drop it without spending the
        // pull request — the retry then still has one outstanding.
        if (facelet == null) return [];
        _pullPending = false;
        _moveCnt = val(152, 160);
        _cube.fromFacelet(facelet);
        _prevMoveCnt = _moveCnt;
        return [MoyuStateEvent(CubeState(facelet))];

      case 164:
        final level = val(8, 16);
        _batteryLevel = level;
        return [MoyuBatteryEvent(level)];

      case 165:
        _moveCnt = val(88, 96);
        if (_moveCnt == _prevMoveCnt || _prevMoveCnt == -1) return [];
        final timeOffs = <int>[];
        final moves = <CubeMove>[];
        for (var i = 0; i < 5; i++) {
          final m = val(96 + i * 5, 101 + i * 5);
          timeOffs.add(val(8 + i * 16, 24 + i * 16));
          if (m >= 12) return []; // invalid move byte — drop the packet
          moves.add(CubeMove(
            face: _faceByCode[m >> 1],
            prime: (m & 1) == 1,
            cubeTimestamp: Duration.zero, // filled in below
          ));
        }
        return _emitMoves(timeOffs, moves, hostTimeMs);

      default:
        return [];
    }
  }

  List<MoyuEvent> _emitMoves(
      List<int> timeOffs, List<CubeMove> moves, int hostTimeMs) {
    final moveDiff = (_moveCnt - _prevMoveCnt) & 0xff;
    _prevMoveCnt = _moveCnt;
    // A packet only carries the last 5 moves. More than that means notifications
    // were missed (radio drop, or the cube waking from sleep): the moves in
    // between are gone for good, so applying the ones we did get would leave the
    // model silently wrong — and nothing would ever complete again. Declare the
    // model dead instead and let the driver pull a fresh state.
    if (moveDiff > moves.length) {
      _prevMoveCnt = -1;
      return [MoyuDesyncEvent(moveDiff - moves.length)];
    }

    var calcTs = _deviceTime + _deviceTimeOffset;
    for (var i = moveDiff - 1; i >= 0; i--) {
      calcTs += timeOffs[i];
    }
    if (_deviceTime == 0 || (hostTimeMs - calcTs).abs() > 2000) {
      _deviceTime += hostTimeMs - calcTs;
    }

    final events = <MoyuEvent>[];
    for (var i = moveDiff - 1; i >= 0; i--) {
      final m = moves[i];
      _cube.applyMove(m.face, m.prime);
      _deviceTime += timeOffs[i];
      events.add(MoyuMoveEvent(
        CubeMove(
          face: m.face,
          prime: m.prime,
          cubeTimestamp: Duration(milliseconds: _deviceTime),
          hostTimestamp:
              i == 0 ? DateTime.fromMillisecondsSinceEpoch(hostTimeMs) : null,
        ),
        CubeState(_cube.toFaceCube()),
      ));
    }
    _deviceTimeOffset = hostTimeMs - _deviceTime;
    return events;
  }

  /// Decode the facelet bits, or `null` when they cannot describe a real cube:
  /// a colour code above 5, or a colour not appearing exactly 9 times. Both are
  /// impossible from the cube and typical of a wrong decryption key.
  static String? _parseFacelet(String faceletBits) {
    const faces = [2, 5, 0, 3, 4, 1]; // read URFDLB from the FBUDLR-ordered data
    const cs = 'FBUDLR';
    final out = StringBuffer();
    final seen = List<int>.filled(cs.length, 0);
    for (var i = 0; i < 6; i++) {
      final base = faces[i] * 24;
      for (var j = 0; j < 8; j++) {
        final c = int.parse(faceletBits.substring(base + j * 3, base + j * 3 + 3), radix: 2);
        if (c >= cs.length) return null;
        seen[c]++;
        out.write(cs[c]);
        if (j == 3) {
          seen[faces[i]]++;
          out.write(cs[faces[i]]);
        }
      }
    }
    if (seen.any((n) => n != 9)) return null;
    return out.toString();
  }
}
