import '../crypto/gan_cipher.dart';
import '../cube/cubie_cube.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';
import 'gan_gen2_parser.dart';
import 'gan_gen3_parser.dart';
import 'gan_protocol.dart';

/// Pure decoder + protocol parser for GAN Gen4 cubes (GAN12 ui Maglev, GAN14 ui
/// FreePlay).
///
/// Same shape as Gen3 — one move per packet, gaps recovered from the cube's move
/// history through a [GanMoveBuffer] — with different framing and opcodes. The
/// one real difference is hardware info, which Gen4 dribbles out across four
/// separate events instead of one.
///
/// Ported from `afedotov/gan-web-bluetooth` (MIT).
class GanGen4Parser implements GanProtocol {
  static const int _messageBytes = 20;

  /// A move's 6-bit face code, in `"URFDLB"` order.
  static const List<int> _faceCodes = [2, 32, 8, 1, 16, 4];

  /// The same faces again, as move history packs them into 3 bits.
  static const List<int> _historyFaceCodes = [1, 5, 3, 0, 4, 2];

  static const List<Face> _faces = [
    Face.U,
    Face.R,
    Face.F,
    Face.D,
    Face.L,
    Face.B,
  ];

  /// A facelets event arriving within this of a live move is ignored for
  /// gap-checking: mid-turn, the model is *expected* to trail the cube.
  static const int _moveSettleMs = 500;

  /// The only Gen4 cube with a gyro.
  static const String _gyroHardware = 'GAN12uiM';

  final GanCipher _cipher;
  final CubieCube _cube = CubieCube();
  final GanMoveBuffer _buffer = GanMoveBuffer();

  /// Hardware info arrives in pieces, keyed by the event that carried each.
  final Map<int, String> _hwInfo = {};

  int _lastMoveHostMs = 0;
  int? _batteryLevel;

  GanGen4Parser(List<int> macBytes)
      : _cipher = GanCipher.forMac(
            GanGen2Parser.baseKey, GanGen2Parser.baseIv, macBytes);

  @override
  int? get batteryLevel => _batteryLevel;

  @override
  CubeState get currentState => CubeState(_cube.toFaceCube());

  @override
  bool get needsAnchor => _buffer.needsAnchor;

  @override
  void setState(CubeState state) => _cube.fromFacelet(state.facelets);

  @override
  List<int> encodeRequest(GanRequest request) {
    final msg = List<int>.filled(_messageBytes, 0);
    switch (request) {
      case GanRequest.facelets:
        msg.setAll(0, [0xDD, 0x04, 0x00, 0xED, 0x00, 0x00]);
      case GanRequest.hardware:
        _hwInfo.clear(); // a fresh set of pieces is on its way
        msg.setAll(0, [0xDF, 0x03, 0x00, 0x00, 0x00]);
      case GanRequest.battery:
        msg.setAll(0, [0xDD, 0x04, 0x00, 0xEF, 0x00, 0x00]);
      case GanRequest.reset:
        msg.setAll(0, [
          0xD2, 0x0D, 0x05, 0x39, 0x77, 0x00, 0x00, 0x01, //
          0x23, 0x45, 0x67, 0x89, 0xAB, 0x00, 0x00, 0x00,
        ]);
    }
    return _cipher.encode(msg);
  }

  @override
  List<int> encodeMoveHistory(int serial, int count) {
    final (s, c) = GanGen3Parser.alignHistoryWindow(serial, count);
    final msg = List<int>.filled(_messageBytes, 0);
    msg.setAll(0, [0xD1, 0x04, s, 0, c, 0]);
    return _cipher.encode(msg);
  }

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
    int valLe(int start, int bytes) {
      var v = 0;
      for (var i = 0; i < bytes; i++) {
        v |= val(start + i * 8, 8) << (i * 8);
      }
      return v;
    }

    // Guard every branch against a packet too short to hold what it reads: this
    // runs on raw radio input, and a truncated notification must not throw.
    bool has(int bitCount) => s.length >= bitCount;

    if (!has(16)) return [];
    final eventType = val(0, 8);
    final dataLength = val(8, 8);

    switch (eventType) {
      case 0x01:
        if (!has(72)) return [];
        return _parseMove(val, valLe, hostTimeMs);
      case 0xD1:
        return _parseMoveHistory(val, dataLength, s.length, hostTimeMs);
      case 0xED:
        if (!has(124)) return [];
        return _parseFacelets(val, valLe, hostTimeMs);
      case 0xEF:
        if (!has(16 + dataLength * 8)) return [];
        _batteryLevel = val(8 + dataLength * 8, 8).clamp(0, 100);
        return [GanBatteryEvent(_batteryLevel!)];
      case >= 0xFA && <= 0xFE:
        return _parseHardware(val, has, eventType, dataLength);
      default:
        // 0xEC is the gyro stream: the trainer takes orientation from a setting,
        // so it is decoded by nobody and dropped here.
        return [];
    }
  }

  List<GanEvent> _parseMove(int Function(int, int) val,
      int Function(int, int) valLe, int hostTimeMs) {
    if (needsAnchor) return [];
    _lastMoveHostMs = hostTimeMs;

    final cubeTimeMs = valLe(16, 4);
    final serial = valLe(48, 2);
    final prime = val(64, 2) == 1;
    final face = _faceCodes.indexOf(val(66, 6));
    if (face < 0) return []; // corrupt packet — drop it

    return _drain(_buffer.push(BufferedMove(
      serial: serial,
      face: _faces[face],
      prime: prime,
      cubeTimeMs: cubeTimeMs,
      hostTimeMs: hostTimeMs,
    )));
  }

  List<GanEvent> _parseMoveHistory(
      int Function(int, int) val, int dataLength, int bitLength, int hostTimeMs) {
    if (needsAnchor) return [];
    final startSerial = val(16, 8);
    // The cube's own length field decides how many moves follow, so clamp it to
    // what the packet can actually hold.
    final count = ((dataLength - 1) * 2).clamp(0, (bitLength - 24) ~/ 4);

    final events = <GanEvent>[];
    for (var i = 0; i < count; i++) {
      final face = _historyFaceCodes.indexOf(val(24 + 4 * i, 3));
      if (face < 0) continue;
      events.addAll(_drain(_buffer.injectHistory(BufferedMove(
        serial: (startSerial - i) & 0xFF,
        face: _faces[face],
        prime: val(27 + 4 * i, 1) == 1,
      ))));
    }
    return events;
  }

  List<GanEvent> _parseFacelets(int Function(int, int) val,
      int Function(int, int) valLe, int hostTimeMs) {
    final serial = valLe(16, 2);

    final cp = <int>[];
    final co = <int>[];
    final ep = <int>[];
    final eo = <int>[];
    for (var i = 0; i < 7; i++) {
      cp.add(val(32 + i * 3, 3));
      co.add(val(53 + i * 2, 2));
    }
    for (var i = 0; i < 11; i++) {
      ep.add(val(69 + i * 4, 4));
      eo.add(val(113 + i, 1));
    }
    cp.add(28 - cp.reduce((a, b) => a + b));
    co.add((3 - co.reduce((a, b) => a + b) % 3) % 3);
    ep.add(66 - ep.reduce((a, b) => a + b));
    eo.add((2 - eo.reduce((a, b) => a + b) % 2) % 2);

    // The cube sends facelets periodically, so they double as a check that the
    // model has not silently fallen behind.
    if (!needsAnchor) {
      if (hostTimeMs - _lastMoveHostMs <= _moveSettleMs) return [];
      final request = _buffer.checkForMissedMoves(serial);
      if (request != null) {
        return [GanHistoryRequestEvent(request.serial, request.count)];
      }
      // Only a snapshot level with the model can be applied; an older one would
      // rewind it.
      if (((serial - _buffer.lastSerial) & 0xFF) != 0) return [];
    }

    if (!_cube.fromPermutation(cp, co, ep, eo)) return []; // corrupt packet
    _buffer.anchor(serial);
    return [GanStateEvent(CubeState(_cube.toFaceCube()))];
  }

  /// Gen4 splits hardware info across four events; report once all have landed.
  List<GanEvent> _parseHardware(
      int Function(int, int) val, bool Function(int) has, int eventType, int dataLength) {
    switch (eventType) {
      case 0xFA: // product date
        if (!has(56)) return [];
        final year = val(24, 8) | val(32, 8) << 8;
        _hwInfo[eventType] = '${year.toString().padLeft(4, '0')}-'
            '${val(40, 8).toString().padLeft(2, '0')}-'
            '${val(48, 8).toString().padLeft(2, '0')}';
      case 0xFC: // hardware name
        if (!has(24 + (dataLength - 1) * 8)) return [];
        final name = StringBuffer();
        for (var i = 0; i < dataLength - 1; i++) {
          name.writeCharCode(val(i * 8 + 24, 8));
        }
        _hwInfo[eventType] = name.toString();
      case 0xFD: // software version
        if (!has(32)) return [];
        _hwInfo[eventType] = '${val(24, 4)}.${val(28, 4)}';
      case 0xFE: // hardware version
        if (!has(32)) return [];
        _hwInfo[eventType] = '${val(24, 4)}.${val(28, 4)}';
      default:
        return [];
    }

    if (_hwInfo.length < 4) return [];
    final name = _hwInfo[0xFC] ?? '';
    return [
      GanInfoEvent(
        name.trim(),
        _hwInfo[0xFE] ?? '',
        _hwInfo[0xFD] ?? '',
        name == _gyroHardware,
      ),
    ];
  }

  /// Turn a buffer verdict into events, applying the moves it released.
  List<GanEvent> _drain(GanBufferResult result) {
    final events = <GanEvent>[];
    for (final m in result.evicted) {
      _cube.applyMove(m.face, m.prime);
      events.add(GanMoveEvent(
        CubeMove(
          face: m.face,
          prime: m.prime,
          cubeTimestamp: Duration(milliseconds: m.cubeTimeMs ?? 0),
          hostTimestamp: m.hostTimeMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(m.hostTimeMs!),
        ),
        CubeState(_cube.toFaceCube()),
      ));
    }
    if (result.desynced) {
      events.add(GanDesyncEvent(result.lostMoves));
    } else if (result.historyRequest != null) {
      events.add(GanHistoryRequestEvent(
          result.historyRequest!.serial, result.historyRequest!.count));
    }
    return events;
  }
}
