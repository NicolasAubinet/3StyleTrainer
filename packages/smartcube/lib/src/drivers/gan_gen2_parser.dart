import '../crypto/gan_cipher.dart';
import '../cube/cubie_cube.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';
import 'gan_protocol.dart';

/// Pure decoder + protocol parser for GAN Gen2 cubes — the GAN 356 i3, i Carry
/// (S), GAN12 ui, GAN Mini ui FreePlay and Monster Go 3Ai, plus the MoYu AI 2023
/// which speaks the same protocol with a different key.
///
/// Ported from `afedotov/gan-web-bluetooth` (MIT). No BLE/Flutter dependencies —
/// feed it raw packets and it emits [GanEvent]s while tracking full cube state.
class GanGen2Parser implements GanProtocol {
  /// Base key/IV for GAN Gen2/3/4 cubes.
  static const List<int> baseKey = [
    0x01, 0x02, 0x42, 0x28, 0x31, 0x91, 0x16, 0x07, //
    0x20, 0x05, 0x18, 0x54, 0x42, 0x11, 0x12, 0x53,
  ];
  static const List<int> baseIv = [
    0x11, 0x03, 0x32, 0x28, 0x21, 0x01, 0x76, 0x27, //
    0x20, 0x95, 0x78, 0x14, 0x32, 0x12, 0x02, 0x43,
  ];

  /// The MoYu AI 2023 (`AiCube`) speaks Gen2 with its own key.
  static const List<int> moyuAiKey = [
    0x05, 0x12, 0x02, 0x45, 0x02, 0x01, 0x29, 0x56, //
    0x12, 0x78, 0x12, 0x76, 0x81, 0x01, 0x08, 0x03,
  ];
  static const List<int> moyuAiIv = [
    0x01, 0x44, 0x28, 0x06, 0x86, 0x21, 0x22, 0x28, //
    0x51, 0x05, 0x08, 0x31, 0x82, 0x02, 0x21, 0x06,
  ];

  /// Opcodes written to the cube's command characteristic.
  static const int opFacelets = 0x04;
  static const int opHardware = 0x05;
  static const int opBattery = 0x09;

  /// Tells the cube its current position *is* solved. Unlike the other requests
  /// this is a fixed payload, not a bare opcode.
  static const List<int> _resetRequest = [
    0x0A, 0x05, 0x39, 0x77, 0x00, 0x00, 0x01, 0x23, 0x45, 0x67, //
    0x89, 0xAB, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ];

  /// A move's 4-bit face code indexes this order (`"URFDLB"[code]`).
  static const List<Face> _faceByCode = [
    Face.U,
    Face.R,
    Face.F,
    Face.D,
    Face.L,
    Face.B,
  ];

  /// A packet carries at most the last 7 moves.
  static const int _maxRecoverableMoves = 7;

  final GanCipher _cipher;
  final CubieCube _cube = CubieCube();

  int _lastSerial = -1;
  int _deviceTime = 0;
  int _deviceTimeOffset = 0;
  int _lastMoveTimeMs = 0;
  int? _batteryLevel;

  GanGen2Parser(List<int> macBytes, {bool moyuAi = false})
      : _cipher = GanCipher.forMac(moyuAi ? moyuAiKey : baseKey,
            moyuAi ? moyuAiIv : baseIv, macBytes);

  @override
  int? get batteryLevel => _batteryLevel;

  @override
  CubeState get currentState => CubeState(_cube.toFaceCube());

  /// `true` while the model is untrusted: moves are dropped until facelets
  /// re-anchor it (before the first state, or after a [GanDesyncEvent]).
  @override
  bool get needsAnchor => _lastSerial == -1;

  /// Force the next facelets message to re-anchor (used after packet loss).
  void resetAnchor() => _lastSerial = -1;

  @override
  void setState(CubeState state) => _cube.fromFacelet(state.facelets);

  @override
  List<int> encodeRequest(GanRequest request) {
    if (request == GanRequest.reset) {
      return _cipher.encode(List<int>.of(_resetRequest));
    }
    final req = List<int>.filled(20, 0);
    req[0] = switch (request) {
      GanRequest.facelets => opFacelets,
      GanRequest.hardware => opHardware,
      GanRequest.battery => opBattery,
      GanRequest.reset => 0, // unreachable
    };
    return _cipher.encode(req);
  }

  @override
  List<int>? encodeMoveHistory(int serial, int count) =>
      null; // a Gen2 packet already carries the last 7 moves

  @override
  List<GanEvent> parse(List<int> raw, int hostTimeMs) {
    final data = _cipher.decode(raw);
    final bits = StringBuffer();
    for (final b in data) {
      bits.write(b.toRadixString(2).padLeft(8, '0'));
    }
    final s = bits.toString();
    int val(int start, int length) =>
        int.parse(s.substring(start, start + length), radix: 2);

    // Guard every branch against a packet too short to hold what it reads: this
    // runs on raw radio input, and a truncated notification must not throw.
    bool has(int bitCount) => s.length >= bitCount;

    if (!has(4)) return [];
    switch (val(0, 4)) {
      case 0x02:
        return _parseMoves(val, has, hostTimeMs);
      case 0x04:
        if (!has(102)) return [];
        return _parseFacelets(val);
      case 0x05:
        if (!has(105)) return [];
        final name = StringBuffer();
        for (var i = 0; i < 8; i++) {
          name.writeCharCode(val(i * 8 + 40, 8));
        }
        return [
          GanInfoEvent(
            name.toString().trim(),
            '${val(8, 8)}.${val(16, 8)}',
            '${val(24, 8)}.${val(32, 8)}',
            val(104, 1) == 1,
          ),
        ];
      case 0x09:
        if (!has(16)) return [];
        _batteryLevel = val(8, 8).clamp(0, 100);
        return [GanBatteryEvent(_batteryLevel!)];
      case 0x0D:
        return [GanDisconnectEvent()];
      default:
        // 0x01 is the gyro stream: the trainer takes orientation from a setting,
        // so it is decoded by nobody and dropped here.
        return [];
    }
  }

  List<GanEvent> _parseMoves(
      int Function(int, int) val, bool Function(int) has, int hostTimeMs) {
    if (!has(12)) return [];
    if (needsAnchor) return []; // no trusted model to apply moves to

    final serial = val(4, 8);
    final missed = (serial - _lastSerial) & 0xFF;
    if (missed == 0) return [];
    _lastSerial = serial;

    // Beyond what the packet carries, the moves in between are gone for good:
    // applying the ones we did get would leave the model silently wrong, and
    // nothing would ever complete again. Declare the model dead instead.
    if (missed > _maxRecoverableMoves) {
      _lastSerial = -1;
      return [GanDesyncEvent(missed - _maxRecoverableMoves)];
    }

    if (!has(47 + 16 * missed)) return [];

    // Move 0 is the newest; walk oldest-first so the model and clock advance in
    // the order the turns actually happened.
    final faces = <Face>[];
    final primes = <bool>[];
    final elapsed = <int>[];
    for (var i = 0; i < missed; i++) {
      final face = val(12 + 5 * i, 4);
      if (face >= _faceByCode.length) return []; // corrupt packet — drop it
      faces.add(_faceByCode[face]);
      primes.add(val(16 + 5 * i, 1) == 1);
      var ms = val(47 + 16 * i, 16);
      // A zero elapsed means the cube's 16-bit clock register wrapped; fall back
      // to how long the host waited (nothing to measure against on the first move).
      if (ms == 0) ms = _lastMoveTimeMs == 0 ? 0 : hostTimeMs - _lastMoveTimeMs;
      elapsed.add(ms);
    }

    var calcTs = _deviceTime + _deviceTimeOffset;
    for (var i = missed - 1; i >= 0; i--) {
      calcTs += elapsed[i];
    }
    if (_deviceTime == 0 || (hostTimeMs - calcTs).abs() > 2000) {
      _deviceTime += hostTimeMs - calcTs;
    }

    final events = <GanEvent>[];
    for (var i = missed - 1; i >= 0; i--) {
      _cube.applyMove(faces[i], primes[i]);
      _deviceTime += elapsed[i];
      events.add(GanMoveEvent(
        CubeMove(
          face: faces[i],
          prime: primes[i],
          cubeTimestamp: Duration(milliseconds: _deviceTime),
          // Recovered moves were never seen live, so they have no host time.
          hostTimestamp:
              i == 0 ? DateTime.fromMillisecondsSinceEpoch(hostTimeMs) : null,
        ),
        CubeState(_cube.toFaceCube()),
      ));
    }
    _deviceTimeOffset = hostTimeMs - _deviceTime;
    _lastMoveTimeMs = hostTimeMs;
    return events;
  }

  List<GanEvent> _parseFacelets(int Function(int, int) val) {
    final serial = val(4, 8);
    // Facelets snapshot the cube at *its* serial. Once anchored, an older
    // snapshot means moves have landed since — applying it would rewind the
    // model, so leave it and wait for a fresh pull.
    if (!needsAnchor && serial != _lastSerial) return [];

    final cp = <int>[];
    final co = <int>[];
    final ep = <int>[];
    final eo = <int>[];
    for (var i = 0; i < 7; i++) {
      cp.add(val(12 + i * 3, 3));
      co.add(val(33 + i * 2, 2));
    }
    for (var i = 0; i < 11; i++) {
      ep.add(val(47 + i * 4, 4));
      eo.add(val(91 + i, 1));
    }
    // The last corner and edge are not sent — they are whatever makes the
    // permutation sum and the orientation parity work out.
    cp.add(28 - cp.reduce((a, b) => a + b));
    co.add((3 - co.reduce((a, b) => a + b) % 3) % 3);
    ep.add(66 - ep.reduce((a, b) => a + b));
    eo.add((2 - eo.reduce((a, b) => a + b) % 2) % 2);

    if (!_cube.fromPermutation(cp, co, ep, eo)) return []; // corrupt packet
    _lastSerial = serial;
    return [GanStateEvent(CubeState(_cube.toFaceCube()))];
  }
}
