import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/src/crypto/aes128.dart';
import 'package:smartcube/src/driver.dart';
import 'package:smartcube/src/drivers/qiyi_driver.dart';
import 'package:smartcube/src/drivers/qiyi_parser.dart';
import 'package:smartcube/src/model/cube_move.dart';
import 'package:smartcube/src/model/cube_state.dart';

void main() {
  const mac = 'CC:A3:00:00:AB:CD';
  final macBytes = QiyiDriver.macBytes(mac);
  final aes = Aes128(QiyiParser.fixedKey);

  QiyiParser newParser() => QiyiParser(macBytes);

  List<int> mapBlocks(List<int> data, List<int> Function(List<int>) f) {
    final out = List<int>.of(data);
    for (var off = 0; off + 16 <= out.length; off += 16) {
      out.setRange(off, off + 16, f(out.sublist(off, off + 16)));
    }
    return out;
  }

  /// Frame + CRC + zero-pad + encrypt, the way the cube would send it.
  List<int> frame(List<int> content) {
    final msg = <int>[0xFE, content.length + 4, ...content];
    final crc = QiyiParser.crc16Modbus(msg);
    msg
      ..add(crc & 0xFF)
      ..add(crc >> 8);
    while (msg.length % 16 != 0) {
      msg.add(0);
    }
    return mapBlocks(msg, aes.encrypt);
  }

  List<int> unframe(List<int> raw) => mapBlocks(raw, aes.decrypt);

  List<int> beU32(int v) =>
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  /// 54 facelets → 27 colour-nibble bytes, low nibble first.
  List<int> stateBytes(String facelets) {
    const colour = {'L': 0, 'R': 1, 'D': 2, 'U': 3, 'F': 4, 'B': 5};
    return [
      for (var i = 0; i < 27; i++)
        colour[facelets[i * 2]]! | (colour[facelets[i * 2 + 1]]! << 4),
    ];
  }

  List<int> cubeHello(String facelets, {int battery = 88, int ticks = 1000}) =>
      frame([
        QiyiParser.opCubeHello,
        ...beU32(ticks),
        ...stateBytes(facelets),
        0, // byte 34 — not a field we read on this message
        battery,
      ]);

  List<int> stateChange(
    String facelets, {
    int move = 0,
    int battery = 88,
    int ticks = 1000,
    bool needsAck = false,
  }) =>
      frame([
        QiyiParser.opStateChange,
        ...beU32(ticks),
        ...stateBytes(facelets),
        move,
        battery,
        ...List<int>.filled(55, 0), // bytes 36..90
        needsAck ? 1 : 0,
      ]);

  // A solved cube with U turned clockwise, in facelet terms.
  const uFacelets = 'UUUUUUUUUBBBRRRRRRRRRFFFFFFDDDDDDDDDFFFLLLLLLLLLBBBBBB';

  group('framing', () {
    test('CRC-16/MODBUS matches the standard check vector', () {
      // "123456789" → 0x4B37, the published MODBUS check value.
      expect(QiyiParser.crc16Modbus('123456789'.codeUnits), 0x4B37);
    });

    test('app hello carries the prefix and the MAC reversed, framed and padded',
        () {
      final msg = unframe(newParser().encodeAppHello());
      expect(msg[0], 0xFE);
      expect(msg[1], 21); // 11 prefix + 6 MAC + 4
      expect(msg.sublist(2, 13),
          [0x00, 0x6B, 0x01, 0x00, 0x00, 0x22, 0x06, 0x00, 0x02, 0x08, 0x00]);
      expect(msg.sublist(13, 19), [0xCD, 0xAB, 0x00, 0x00, 0xA3, 0xCC]);
      final crc = QiyiParser.crc16Modbus(msg.sublist(0, 19));
      expect([msg[19], msg[20]], [crc & 0xFF, crc >> 8]);
      expect(msg.length % 16, 0);
      expect(msg.sublist(21), everyElement(0)); // zero padding
    });

    test('request state is the documented [5,5,5,5,5] content', () {
      final msg = unframe(newParser().encodeRequestState());
      expect(msg[1], 9);
      expect(msg.sublist(2, 7), [5, 5, 5, 5, 5]);
    });

    test('a corrupt packet is dropped, not decoded', () {
      final raw = cubeHello(CubeState.solvedFacelets);
      raw[3] ^= 0xFF; // one flipped bit in the ciphertext fails the CRC
      expect(newParser().parse(raw, 1000), isEmpty);
    });

    test('a truncated packet is dropped without throwing', () {
      final raw = stateChange(CubeState.solvedFacelets, move: 8);
      for (final len in [0, 16, 32, 64, 80]) {
        expect(newParser().parse(raw.sublist(0, len), 1000), isEmpty);
      }
    });
  });

  group('state decoding', () {
    test('solved encodes to the byte pattern the spec quotes', () {
      final bytes = stateBytes(CubeState.solvedFacelets);
      expect(bytes.sublist(0, 10),
          [0x33, 0x33, 0x33, 0x33, 0x13, 0x11, 0x11, 0x11, 0x11, 0x44]);
    });

    test('cube hello decodes to solved, acks, and reports battery', () {
      final events = newParser().parse(cubeHello(CubeState.solvedFacelets), 1000);

      final ack = events.whereType<QiyiAckRequestEvent>().single;
      final acked = unframe(ack.message);
      expect(acked[1], 9);
      // The ack echoes the acked message's opcode and timestamp.
      expect(acked.sublist(2, 7), [QiyiParser.opCubeHello, ...beU32(1000)]);

      expect(events.whereType<QiyiBatteryEvent>().single.level, 88);
      expect(events.whereType<QiyiHelloEvent>().single.state,
          CubeState.solved);
    });

    test('a state change carries the move and the full state after it', () {
      final parser = newParser();
      parser.parse(cubeHello(CubeState.solvedFacelets), 1000);
      final events = parser.parse(stateChange(uFacelets, move: 8), 2000);

      final e = events.whereType<QiyiMoveEvent>().single;
      expect(e.move.face, Face.U);
      expect(e.move.prime, isFalse);
      expect(e.stateAfter.facelets, uFacelets);
      expect(events, isNot(contains(isA<QiyiAckRequestEvent>())));
    });

    test('every move code maps to the documented face and direction', () {
      const expected = [
        (Face.L, true), (Face.L, false), //
        (Face.R, true), (Face.R, false),
        (Face.D, true), (Face.D, false),
        (Face.U, true), (Face.U, false),
        (Face.F, true), (Face.F, false),
        (Face.B, true), (Face.B, false),
      ];
      for (var code = 1; code <= 12; code++) {
        final events =
            newParser().parse(stateChange(uFacelets, move: code), 1000);
        final e = events.whereType<QiyiMoveEvent>().single;
        expect((e.move.face, e.move.prime), expected[code - 1],
            reason: 'move code $code');
      }
    });

    test('move code 0 is a state change with no move', () {
      final events = newParser().parse(stateChange(uFacelets), 1000);
      expect(events.whereType<QiyiMoveEvent>(), isEmpty);
      expect(events.whereType<QiyiStateEvent>().single.state.facelets,
          uFacelets);
    });

    test('an out-of-range colour nibble drops the packet', () {
      final raw = stateChange(CubeState.solvedFacelets, move: 8);
      final msg = unframe(raw);
      msg[7] = 0x63; // nibble 6 — no such face
      final crc = QiyiParser.crc16Modbus(msg.sublist(0, msg[1] - 2));
      msg[msg[1] - 2] = crc & 0xFF;
      msg[msg[1] - 1] = crc >> 8;
      final events = newParser().parse(mapBlocks(msg, aes.encrypt), 1000);
      expect(events.whereType<QiyiMoveEvent>(), isEmpty);
      expect(events.whereType<QiyiStateEvent>(), isEmpty);
    });
  });

  group('the needs-ACK solved glitch', () {
    test('needs-ACK means solved even when the state bytes disagree', () {
      // The firmware can skip the solved state change during fast slice moves
      // and send this instead. Trusting the bytes would desync the model.
      final events =
          newParser().parse(stateChange(uFacelets, move: 8, needsAck: true), 1000);

      expect(events.whereType<QiyiMoveEvent>().single.stateAfter,
          CubeState.solved);
      expect(events.whereType<QiyiAckRequestEvent>(), hasLength(1));
    });

    test('the ack echoes the state change being acknowledged', () {
      final events = newParser()
          .parse(stateChange(uFacelets, needsAck: true, ticks: 4242), 1000);
      final acked = unframe(events.whereType<QiyiAckRequestEvent>().single.message);
      expect(acked.sublist(2, 7), [QiyiParser.opStateChange, ...beU32(4242)]);
    });

    test('a normal state change is not acked and is taken at face value', () {
      final events = newParser().parse(stateChange(uFacelets, move: 8), 1000);
      expect(events.whereType<QiyiAckRequestEvent>(), isEmpty);
      expect(events.whereType<QiyiMoveEvent>().single.stateAfter.isSolved,
          isFalse);
    });
  });

  test('battery is clamped to 100', () {
    final events =
        newParser().parse(cubeHello(CubeState.solvedFacelets, battery: 255), 1000);
    expect(events.whereType<QiyiBatteryEvent>().single.level, 100);
  });

  test('battery is null until the cube reports one', () {
    final parser = newParser();
    expect(parser.batteryLevel, isNull);
    parser.parse(cubeHello(CubeState.solvedFacelets, battery: 0), 1000);
    expect(parser.batteryLevel, 0);
  });

  group('cube clock', () {
    Duration stamp(QiyiParser p, int ticks, int hostMs) => p
        .parse(stateChange(uFacelets, move: 8, ticks: ticks), hostMs)
        .whereType<QiyiMoveEvent>()
        .single
        .move
        .cubeTimestamp;

    test('the first move anchors the cube clock onto host time', () {
      expect(stamp(newParser(), 1000, 50000).inMilliseconds, 50000);
    });

    test('later moves advance by the cube clock, at 1.6ms per tick', () {
      final parser = newParser();
      stamp(parser, 1000, 50000); // anchor
      // 625 ticks on = 1000ms on the cube's clock, whatever the host reports.
      expect(stamp(parser, 1625, 50040).inMilliseconds, 51000);
    });

    test('a drift past 2s re-anchors rather than compounding', () {
      final parser = newParser();
      stamp(parser, 1000, 50000);
      expect(stamp(parser, 1625, 90000).inMilliseconds, 90000);
    });
  });

  group('MAC derivation', () {
    QiyiDriver driver() => QiyiDriver();

    test('from a QiYi name', () {
      expect(
          QiyiDriver.deriveMac(
              const CubeAdvertisement(id: 'x', name: 'QY-QYSC-1-ABCD')),
          'CC:A3:00:00:AB:CD');
    });

    test('from a Tornado V4 name — same protocol, same trick', () {
      expect(
          QiyiDriver.deriveMac(
              const CubeAdvertisement(id: 'x', name: 'XMD-TornadoV4-i-2-12EF')),
          'CC:A3:00:00:12:EF');
    });

    test('from manufacturer data: the FIRST 6 bytes, reversed', () {
      expect(
          QiyiDriver.deriveMac(const CubeAdvertisement(
            id: 'x',
            name: 'QY-QYSC',
            manufacturerData: {
              0x0504: [0xCD, 0xAB, 0x00, 0x00, 0xA3, 0xCC, 0x99, 0x99]
            },
          )),
          'CC:A3:00:00:AB:CD');
    });

    test('manufacturer data under another CIC is not the MAC', () {
      const adv = CubeAdvertisement(
        id: 'x',
        name: 'QY-QYSC',
        manufacturerData: {
          0x0001: [0xCD, 0xAB, 0x00, 0x00, 0xA3, 0xCC]
        },
      );
      expect(QiyiDriver.deriveMac(adv), isNull);
      expect(driver().needsExplicitMac(adv), isTrue);
    });

    test('a name-derived MAC needs no prompt', () {
      expect(
          driver().needsExplicitMac(
              const CubeAdvertisement(id: 'x', name: 'QY-QYSC-1-ABCD')),
          isFalse);
    });
  });

  group('driver matching', () {
    QiyiDriver driver() => QiyiDriver();

    test('claims both model names', () {
      expect(
          driver().matches(const CubeAdvertisement(id: 'x', name: 'QY-QYSC-1-ABCD')),
          isTrue);
      expect(
          driver().matches(
              const CubeAdvertisement(id: 'x', name: 'XMD-TornadoV4-i-1-ABCD')),
          isTrue);
    });

    test('does NOT claim the fff0 service — GAN Gen1 advertises the same UUID',
        () {
      expect(
          driver().matches(const CubeAdvertisement(
            id: 'x',
            name: 'GAN-1234',
            serviceUuids: ['0000fff0-0000-1000-8000-00805f9b34fb'],
          )),
          isFalse);
    });
  });
}
