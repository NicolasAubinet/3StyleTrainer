import '../crypto/aes128.dart';
import '../model/cube_move.dart';
import '../model/cube_state.dart';

/// One decoded event from the cube's notification stream.
sealed class QiyiEvent {}

/// The cube answered the app's hello. Carries its full state.
class QiyiHelloEvent extends QiyiEvent {
  final CubeState state;
  QiyiHelloEvent(this.state);
}

/// A full state snapshot with no move attached (a pulled state, or a state
/// change the cube reported without naming a face).
class QiyiStateEvent extends QiyiEvent {
  final CubeState state;
  QiyiStateEvent(this.state);
}

/// A single move plus the cube's own full state after it.
class QiyiMoveEvent extends QiyiEvent {
  final CubeMove move;
  final CubeState stateAfter;
  QiyiMoveEvent(this.move, this.stateAfter);
}

class QiyiBatteryEvent extends QiyiEvent {
  final int level;
  QiyiBatteryEvent(this.level);
}

/// The cube wants this message acknowledged. [message] is ready to write as-is.
/// The parser stays pure by asking rather than writing (see the Gen3/Gen4
/// history-request events, same idea).
class QiyiAckRequestEvent extends QiyiEvent {
  final List<int> message;
  QiyiAckRequestEvent(this.message);
}

/// Pure decoder + protocol parser for the QiYi Smart Cube (`QY-QYSC`) and the
/// Tornado V4 (`XMD-TornadoV4-i`, same protocol), from the reverse-engineered
/// spec at `codeberg.org/Flying-Toast/qiyi_smartcube_protocol` and csTimer
/// `qiyicube.js` (GPL-3.0). No BLE/Flutter dependencies.
///
/// Unlike every other brand here, **the cube is authoritative**: each state
/// change carries the full facelet state, so there is no move tracking, no
/// [CubieCube], no serial, and consequently no desync to detect or heal. The
/// move byte is informational — the state is the truth.
class QiyiParser {
  /// The QiYi key is fixed firmware-wide — no MAC derivation (the MAC is still
  /// needed, but only as App Hello payload; see [encodeAppHello]).
  static const List<int> fixedKey = [
    0x57, 0xb1, 0xf9, 0xab, 0xcd, 0x5a, 0xe8, 0xa7, //
    0x9c, 0xb9, 0x8c, 0xe7, 0x57, 0x8c, 0x51, 0x08,
  ];

  /// Cube→app opcodes, at byte 2 of a decoded message.
  static const int opCubeHello = 0x02;
  static const int opStateChange = 0x03;
  static const int opSyncConfirmation = 0x04;
  static const int opCurrentState = 0x05;

  static const int _msgHeader = 0xFE;

  /// App Hello content, less the trailing MAC.
  static const List<int> _appHelloPrefix = [
    0x00, 0x6B, 0x01, 0x00, 0x00, 0x22, 0x06, 0x00, 0x02, 0x08, 0x00, //
  ];

  /// Facelet nibble → face letter: 0=orange(L) 1=red(R) 2=yellow(D) 3=white(U)
  /// 4=green(F) 5=blue(B).
  static const String _faceByColour = 'LRDUFB';

  /// Move byte `1..12`, in the cube's order: `L' L R' R D' D U' U F' F B' B`.
  static const List<(Face, bool)?> _moveByCode = [
    null,
    (Face.L, true), (Face.L, false), //
    (Face.R, true), (Face.R, false),
    (Face.D, true), (Face.D, false),
    (Face.U, true), (Face.U, false),
    (Face.F, true), (Face.F, false),
    (Face.B, true), (Face.B, false),
  ];

  /// Byte offsets into a decoded message.
  static const int _tsOffset = 3; // u32 big-endian, units of 1.6 ms
  static const int _stateOffset = 7; // 27 bytes → 54 facelet nibbles
  static const int _moveOffset = 34; // state change only
  static const int _batteryOffset = 35;
  static const int _needsAckOffset = 91; // state change only

  final Aes128 _aes = Aes128(fixedKey);
  final List<int> _mac;

  int _batteryLevel = 0;
  int _timeOffset = 0;
  bool _timeAnchored = false;

  QiyiParser(List<int> macBytes) : _mac = List<int>.of(macBytes);

  int get batteryLevel => _batteryLevel;

  /// The first thing the app must write. The cube ignores everything — and
  /// reports nothing — until it has been told its own MAC.
  List<int> encodeAppHello() =>
      _encodeMessage([..._appHelloPrefix, ..._mac.reversed]);

  /// Ask the cube for its current state; answered with [opCurrentState].
  List<int> encodeRequestState() => _encodeMessage(const [5, 5, 5, 5, 5]);

  List<QiyiEvent> parse(List<int> raw, int hostTimeMs) {
    final msg = _decryptAll(raw);
    // Length-bounded from here down: this decodes raw radio input, and a
    // truncated notification must not throw out of the BLE stream handler.
    if (msg.length < 4 || msg[0] != _msgHeader) return const [];
    final length = msg[1];
    if (length < 5 || length > msg.length) return const [];
    final crc = msg[length - 2] | (msg[length - 1] << 8);
    if (crc16Modbus(msg.sublist(0, length - 2)) != crc) return const [];

    switch (msg[2]) {
      case opCubeHello:
        final state = _decodeState(msg, length);
        if (state == null) return const [];
        return [
          QiyiAckRequestEvent(_encodeAck(msg)),
          ..._battery(msg, length),
          QiyiHelloEvent(state),
        ];

      case opStateChange:
        if (!_has(length, _needsAckOffset)) return const [];
        // The cube asks to be acknowledged when it believes it reached solved.
        // Firmware glitch: solving during fast slice moves (an H-perm) can make
        // it skip the solved state change and send this one with a *non-solved*
        // state instead. The spec is explicit — needs-ACK means solved, whatever
        // the state bytes say. Trusting the bytes here would leave the model
        // wrong for the rest of the session.
        final needsAck = msg[_needsAckOffset] == 1;
        final state = needsAck ? CubeState.solved : _decodeState(msg, length);
        final events = <QiyiEvent>[
          if (needsAck) QiyiAckRequestEvent(_encodeAck(msg)),
          ..._battery(msg, length),
        ];
        if (state == null) return events;

        final move = _decodeMove(msg, length);
        events.add(move == null
            ? QiyiStateEvent(state)
            : QiyiMoveEvent(
                CubeMove(
                  face: move.$1,
                  prime: move.$2,
                  cubeTimestamp: _fitTimestamp(msg, hostTimeMs),
                  hostTimestamp: DateTime.fromMillisecondsSinceEpoch(hostTimeMs),
                ),
                state,
              ));
        return events;

      // The spec names this message but not its layout, so the state offset is
      // assumed to match the two that are documented. Being length-bounded, a
      // wrong guess drops the packet instead of inventing a state — and nothing
      // depends on it, since a pull is only ever a convenience here.
      case opCurrentState:
        final state = _decodeState(msg, length);
        return state == null ? const [] : [QiyiStateEvent(state)];

      case opSyncConfirmation:
      default:
        return const [];
    }
  }

  /// `true` when the byte at [index] lies inside the message content — i.e.
  /// before the trailing 2-byte CRC, which a naive `index < length` would read
  /// as data.
  static bool _has(int length, int index) => index < length - 2;

  List<QiyiEvent> _battery(List<int> msg, int length) {
    if (!_has(length, _batteryOffset)) return const [];
    _batteryLevel = msg[_batteryOffset].clamp(0, 100);
    return [QiyiBatteryEvent(_batteryLevel)];
  }

  /// Facelets are 4-bit colour nibbles over 27 bytes, **low nibble first**, in
  /// U,R,F,D,L,B face-block order — which is already our facelet string, so this
  /// is a nibble walk and nothing more. An out-of-range nibble means a corrupt
  /// packet (or a wrong offset): drop it rather than build a bogus state.
  static CubeState? _decodeState(List<int> msg, int length) {
    if (!_has(length, _stateOffset + 26)) return null;
    final out = StringBuffer();
    for (var i = 0; i < 27; i++) {
      final b = msg[_stateOffset + i];
      final lo = b & 0x0F;
      final hi = b >> 4;
      if (lo > 5 || hi > 5) return null;
      out
        ..write(_faceByColour[lo])
        ..write(_faceByColour[hi]);
    }
    return CubeState(out.toString());
  }

  static (Face, bool)? _decodeMove(List<int> msg, int length) {
    if (!_has(length, _moveOffset)) return null;
    final code = msg[_moveOffset];
    return code < _moveByCode.length ? _moveByCode[code] : null;
  }

  /// The cube's clock, pulled onto host time the way the V10/GAN drivers do, so
  /// [CubeMove.cubeTimestamp] means the same thing on every brand. (Nothing in
  /// the trainer reads it — it times host-side — so no regression fit, see the
  /// `cubeTimestampLinearFit` note in the plan.)
  Duration _fitTimestamp(List<int> msg, int hostTimeMs) {
    final ticks = (msg[_tsOffset] << 24) |
        (msg[_tsOffset + 1] << 16) |
        (msg[_tsOffset + 2] << 8) |
        msg[_tsOffset + 3];
    final cubeMs = (ticks * 1.6).round();
    if (!_timeAnchored || (hostTimeMs - (cubeMs + _timeOffset)).abs() > 2000) {
      _timeOffset = hostTimeMs - cubeMs;
      _timeAnchored = true;
    }
    return Duration(milliseconds: cubeMs + _timeOffset);
  }

  /// An ACK echoes bytes 2..6 of the message being acknowledged — its opcode
  /// and timestamp.
  List<int> _encodeAck(List<int> msg) => _encodeMessage(msg.sublist(2, 7));

  /// Frame [content] as `0xFE | length | content | crc16`, where `length` counts
  /// the whole message, then zero-pad to a 16-byte multiple and encrypt.
  List<int> _encodeMessage(List<int> content) {
    final msg = <int>[_msgHeader, content.length + 4, ...content];
    final crc = crc16Modbus(msg);
    msg
      ..add(crc & 0xFF)
      ..add(crc >> 8);
    while (msg.length % 16 != 0) {
      msg.add(0);
    }
    return _encryptAll(msg);
  }

  /// CRC-16/MODBUS — init `0xFFFF`, reflected poly `0xA001`.
  static int crc16Modbus(List<int> data) {
    var crc = 0xFFFF;
    for (final b in data) {
      crc ^= b & 0xFF;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
      }
    }
    return crc;
  }

  // AES-128-ECB over every block — no IV, no chaining. GanCipher does not fit.
  List<int> _decryptAll(List<int> data) => _mapBlocks(data, _aes.decrypt);

  List<int> _encryptAll(List<int> data) => _mapBlocks(data, _aes.encrypt);

  static List<int> _mapBlocks(List<int> data, List<int> Function(List<int>) f) {
    final out = List<int>.of(data);
    for (var off = 0; off + 16 <= out.length; off += 16) {
      out.setRange(off, off + 16, f(out.sublist(off, off + 16)));
    }
    return out;
  }
}
