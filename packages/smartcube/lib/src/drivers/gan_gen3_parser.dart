import '../crypto/gan_cipher.dart';
import '../cube/cubie_cube.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';
import 'gan_gen2_parser.dart';
import 'gan_protocol.dart';

/// Pure decoder + protocol parser for GAN Gen3 cubes (the GAN 356 i Carry 2).
///
/// Unlike Gen2, a packet carries a *single* move, so a dropped notification
/// leaves a hole nothing in the stream can fill. The cube instead keeps a move
/// history that can be asked for: moves queue in a [GanMoveBuffer] until they
/// are contiguous, and a gap emits a [GanHistoryRequestEvent].
///
/// Ported from `afedotov/gan-web-bluetooth` (MIT).
class GanGen3Parser implements GanProtocol {
  /// Every Gen3 packet opens with this.
  static const int magic = 0x55;

  /// Command prefix, shared by every Gen3 request.
  static const int opPrefix = 0x68;
  static const int opFacelets = 0x01;
  static const int opMoveHistory = 0x03;
  static const int opHardware = 0x04;
  static const int opReset = 0x05;
  static const int opBattery = 0x07;

  static const int _messageBytes = 16;

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

  final GanCipher _cipher;
  final CubieCube _cube = CubieCube();
  final GanMoveBuffer _buffer = GanMoveBuffer();

  int _lastMoveHostMs = 0;
  int? _batteryLevel;

  GanGen3Parser(List<int> macBytes)
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
        msg.setAll(0, [opPrefix, opFacelets]);
      case GanRequest.hardware:
        msg.setAll(0, [opPrefix, opHardware]);
      case GanRequest.battery:
        msg.setAll(0, [opPrefix, opBattery]);
      case GanRequest.reset:
        msg.setAll(0, [
          opPrefix, opReset, 0x05, 0x39, 0x77, 0x00, 0x00, 0x01, //
          0x23, 0x45, 0x67, 0x89, 0xAB, 0x00, 0x00, 0x00,
        ]);
    }
    return _cipher.encode(msg);
  }

  @override
  List<int> encodeMoveHistory(int serial, int count) {
    final (s, c) = alignHistoryWindow(serial, count);
    final msg = List<int>.filled(_messageBytes, 0);
    msg.setAll(0, [opPrefix, opMoveHistory, s, 0, c, 0]);
    return _cipher.encode(msg);
  }

  /// History replies are byte-aligned and always start on an odd serial with an
  /// even number of moves, whatever was asked for — so ask for what will come
  /// back. The window is also kept off the 255→0 edge, where the firmware
  /// answers with zero bytes that decode as 'D' moves that never happened.
  static (int, int) alignHistoryWindow(int serial, int count) {
    var s = serial;
    var c = count;
    if (s % 2 == 0) s = (s - 1) & 0xFF;
    if (c % 2 == 1) c++;
    c = c < s + 1 ? c : s + 1;
    return (s, c);
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
    // The 16/32-bit fields are little-endian, so read them byte by byte.
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

    if (!has(24) || val(0, 8) != magic) return [];
    final eventType = val(8, 8);
    final dataLength = val(16, 8);
    if (dataLength == 0) return [];

    switch (eventType) {
      case 0x01:
        if (!has(80)) return [];
        return _parseMove(val, valLe, hostTimeMs);
      case 0x06:
        return _parseMoveHistory(val, dataLength, s.length, hostTimeMs);
      case 0x02:
        if (!has(132)) return [];
        return _parseFacelets(val, valLe, hostTimeMs);
      case 0x07:
        if (!has(88)) return [];
        final name = StringBuffer();
        for (var i = 0; i < 5; i++) {
          name.writeCharCode(val(i * 8 + 32, 8));
        }
        return [
          GanInfoEvent(
            name.toString().trim(),
            '${val(80, 4)}.${val(84, 4)}',
            '${val(72, 4)}.${val(76, 4)}',
            false, // no Gen3 cube has a gyro
          ),
        ];
      case 0x10:
        if (!has(32)) return [];
        _batteryLevel = val(24, 8).clamp(0, 100);
        return [GanBatteryEvent(_batteryLevel!)];
      case 0x11:
        return [GanDisconnectEvent()];
      default:
        return [];
    }
  }

  List<GanEvent> _parseMove(int Function(int, int) val,
      int Function(int, int) valLe, int hostTimeMs) {
    if (needsAnchor) return []; // no trusted model to apply moves to
    _lastMoveHostMs = hostTimeMs;

    final cubeTimeMs = valLe(24, 4);
    final serial = valLe(56, 2);
    final prime = val(72, 2) == 1;
    final face = _faceCodes.indexOf(val(74, 6));
    if (face < 0) return []; // corrupt packet — drop it

    return _drain(
      _buffer.push(BufferedMove(
        serial: serial,
        face: _faces[face],
        prime: prime,
        cubeTimeMs: cubeTimeMs,
        hostTimeMs: hostTimeMs,
      )),
      hostTimeMs,
    );
  }

  List<GanEvent> _parseMoveHistory(int Function(int, int) val, int dataLength,
      int bitLength, int hostTimeMs) {
    if (needsAnchor) return [];
    final startSerial = val(24, 8);
    // The cube's own length field decides how many moves follow, so clamp it to
    // what the packet can actually hold.
    final count = (((dataLength - 1) * 2)).clamp(0, (bitLength - 32) ~/ 4);

    // History runs newest-first from startSerial.
    final events = <GanEvent>[];
    for (var i = 0; i < count; i++) {
      final face = _historyFaceCodes.indexOf(val(32 + 4 * i, 3));
      if (face < 0) continue;
      events.addAll(_drain(
        _buffer.injectHistory(BufferedMove(
          serial: (startSerial - i) & 0xFF,
          face: _faces[face],
          prime: val(35 + 4 * i, 1) == 1,
        )),
        hostTimeMs,
      ));
    }
    return events;
  }

  List<GanEvent> _parseFacelets(int Function(int, int) val,
      int Function(int, int) valLe, int hostTimeMs) {
    final serial = valLe(24, 2);

    final cp = <int>[];
    final co = <int>[];
    final ep = <int>[];
    final eo = <int>[];
    for (var i = 0; i < 7; i++) {
      cp.add(val(40 + i * 3, 3));
      co.add(val(61 + i * 2, 2));
    }
    for (var i = 0; i < 11; i++) {
      ep.add(val(77 + i * 4, 4));
      eo.add(val(121 + i, 1));
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

  /// Turn a buffer verdict into events, applying the moves it released.
  List<GanEvent> _drain(GanBufferResult result, int hostTimeMs) {
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
