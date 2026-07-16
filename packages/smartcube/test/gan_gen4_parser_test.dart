import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/src/crypto/gan_cipher.dart';
import 'package:smartcube/src/cube/cubie_cube.dart';
import 'package:smartcube/src/drivers/gan_gen2_parser.dart';
import 'package:smartcube/src/drivers/gan_gen4_parser.dart';
import 'package:smartcube/src/drivers/gan_protocol.dart';
import 'package:smartcube/src/model/cube_move.dart';

void main() {
  const mac = 'CF:30:16:00:AB:CD';
  final cipher = GanCipher.forMac(
      GanGen2Parser.baseKey, GanGen2Parser.baseIv, GanCipher.macBytes(mac));

  GanGen4Parser newParser() => GanGen4Parser(GanCipher.macBytes(mac));

  const uFacelet = 'UUUUUUUUUBBBRRRRRRRRRFFFFFFDDDDDDDDDFFFLLLLLLLLLBBBBBB';
  const liveFaceCodes = [2, 32, 8, 1, 16, 4];
  const historyFaceCodes = [1, 5, 3, 0, 4, 2];

  List<int> packet(void Function(_Bits) build) {
    final bits = _Bits(20);
    build(bits);
    return cipher.encode(bits.toBytes());
  }

  List<int> facelets(int serial) => packet((b) {
        b.put(0, 8, 0xED);
        b.put(8, 8, 1);
        b.putLe(16, 2, serial);
        for (var i = 0; i < 7; i++) {
          b.put(32 + i * 3, 3, i);
          b.put(53 + i * 2, 2, 0);
        }
        for (var i = 0; i < 11; i++) {
          b.put(69 + i * 4, 4, i);
          b.put(113 + i, 1, 0);
        }
      });

  List<int> movePacket(int serial, int faceIndex,
          {bool prime = false, int cubeTimeMs = 1000}) =>
      packet((b) {
        b.put(0, 8, 0x01);
        b.put(8, 8, 1);
        b.putLe(16, 4, cubeTimeMs);
        b.putLe(48, 2, serial);
        b.put(64, 2, prime ? 1 : 0);
        b.put(66, 6, liveFaceCodes[faceIndex]);
      });

  List<int> historyPacket(int startSerial, List<(int, bool)> moves) =>
      packet((b) {
        b.put(0, 8, 0xD1);
        b.put(8, 8, moves.length ~/ 2 + 1);
        b.put(16, 8, startSerial);
        for (var i = 0; i < moves.length; i++) {
          b.put(24 + 4 * i, 3, historyFaceCodes[moves[i].$1]);
          b.put(27 + 4 * i, 1, moves[i].$2 ? 1 : 0);
        }
      });

  int settled(int hostMs) => hostMs + 1000;

  test('battery packet decodes to level', () {
    // The level sits after the payload, at 8 + dataLength * 8.
    final events = newParser().parse(
        packet((b) => b
          ..put(0, 8, 0xEF)
          ..put(8, 8, 2)
          ..put(24, 8, 77)),
        1000);
    expect((events.single as GanBatteryEvent).level, 77);
  });

  test('facelets packet decodes the solved cube and anchors', () {
    final parser = newParser();
    final events = parser.parse(facelets(5), 1000);
    expect((events.single as GanStateEvent).state.facelets,
        CubieCube.solvedFacelet);
    expect(parser.needsAnchor, isFalse);
  });

  test('a move after an anchor yields the move and resulting state', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    final e = parser.parse(movePacket(6, 0), 1500).single as GanMoveEvent;

    expect(e.move.face, Face.U);
    expect(e.move.prime, isFalse);
    expect(e.stateAfter.facelets, uFacelet);
  });

  test('every face code maps to the right face', () {
    const faces = [Face.U, Face.R, Face.F, Face.D, Face.L, Face.B];
    for (var i = 0; i < faces.length; i++) {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      final e = parser.parse(movePacket(6, i), 1500).single as GanMoveEvent;
      expect(e.move.face, faces[i], reason: 'face index $i');
    }
  });

  test('a prime move decodes with the direction bits set', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    final e = parser.parse(movePacket(6, 1, prime: true), 1500).single
        as GanMoveEvent;
    expect(e.move.face, Face.R);
    expect(e.move.prime, isTrue);
  });

  test('the cube clock is carried through', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    final e = parser.parse(movePacket(6, 0, cubeTimeMs: 4321), 1500).single
        as GanMoveEvent;
    expect(e.move.cubeTimestamp, const Duration(milliseconds: 4321));
  });

  test('a move before any facelets anchor is ignored', () {
    expect(newParser().parse(movePacket(6, 0), 1000), isEmpty);
  });

  test('the gyro stream is dropped', () {
    expect(
        newParser().parse(
            packet((b) => b
              ..put(0, 8, 0xEC)
              ..put(8, 8, 1)),
            1000),
        isEmpty);
  });

  group('gap recovery', () {
    test('a gap holds the move back and asks for history', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      final events = parser.parse(movePacket(8, 0), 1500);

      final request = events.single as GanHistoryRequestEvent;
      expect(request.serial, 8);
      expect(request.count, 3);
      expect(parser.currentState.facelets, CubieCube.solvedFacelet);
    });

    test('history fills the gap and everything replays in order', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      parser.parse(movePacket(8, 0), 1500);

      final events =
          parser.parse(historyPacket(7, [(0, false), (0, false)]), 1600);

      final moves = events.whereType<GanMoveEvent>().toList();
      expect(moves, hasLength(3)); // 6, 7, then the held-back 8
      expect(moves.every((m) => m.move.face == Face.U), isTrue);
      expect(moves[0].move.hostTimestamp, isNull); // recovered
      expect(moves[2].move.hostTimestamp, isNotNull); // seen live
    });

    test('a runaway gap gives up and declares a desync', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);

      final events = <GanEvent>[];
      for (var i = 0; i < 20; i++) {
        events.addAll(parser.parse(movePacket(10 + i, 0), 1500 + i));
      }

      expect(events.whereType<GanDesyncEvent>(), isNotEmpty);
      expect(parser.needsAnchor, isTrue);
      expect(parser.parse(facelets(40), 3000), hasLength(1));
    });
  });

  group('periodic facelets', () {
    test('a facelets running ahead of the model asks for the missed moves', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      final events = parser.parse(facelets(8), settled(1000));

      expect((events.single as GanHistoryRequestEvent).count, 4);
    });

    test('a stale facelets snapshot does not rewind the tracked model', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      parser.parse(movePacket(6, 0), 1500);

      expect(parser.parse(facelets(5), settled(1500)), isEmpty);
      expect(parser.currentState.facelets, uFacelet);
    });

    test('a facelets arriving mid-turn is left alone', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      parser.parse(movePacket(6, 0), 1500);
      expect(parser.parse(facelets(8), 1600), isEmpty);
    });
  });

  group('hardware info', () {
    List<int> hwName(String name) => packet((b) {
          b.put(0, 8, 0xFC);
          b.put(8, 8, name.length + 1);
          for (var i = 0; i < name.length; i++) {
            b.put(24 + i * 8, 8, name.codeUnitAt(i));
          }
        });

    List<int> hwVersion(int event, int major, int minor) => packet((b) {
          b.put(0, 8, event);
          b.put(8, 8, 1);
          b.put(24, 4, major);
          b.put(28, 4, minor);
        });

    List<int> hwDate(int year, int month, int day) => packet((b) {
          b.put(0, 8, 0xFA);
          b.put(8, 8, 1);
          b.putLe(24, 2, year);
          b.put(40, 8, month);
          b.put(48, 8, day);
        });

    test('info is reported only once all four pieces have landed', () {
      final parser = newParser();
      expect(parser.parse(hwDate(2023, 5, 6), 1000), isEmpty);
      expect(parser.parse(hwName('GAN14ui'), 1000), isEmpty);
      expect(parser.parse(hwVersion(0xFD, 3, 4), 1000), isEmpty);

      final events = parser.parse(hwVersion(0xFE, 1, 2), 1000);
      final e = events.single as GanInfoEvent;
      expect(e.hardwareName, 'GAN14ui');
      expect(e.hardwareVersion, '1.2');
      expect(e.softwareVersion, '3.4');
    });

    test('only the GAN12 ui Maglev reports a gyro', () {
      GanInfoEvent info(String name) {
        final parser = newParser();
        parser.parse(hwDate(2023, 5, 6), 1000);
        parser.parse(hwName(name), 1000);
        parser.parse(hwVersion(0xFD, 3, 4), 1000);
        return parser.parse(hwVersion(0xFE, 1, 2), 1000).single as GanInfoEvent;
      }

      expect(info('GAN12uiM').gyroSupported, isTrue);
      expect(info('GAN14ui').gyroSupported, isFalse);
    });

    test('asking again starts a fresh set of pieces', () {
      final parser = newParser();
      parser.parse(hwDate(2023, 5, 6), 1000);
      parser.parse(hwName('GAN14ui'), 1000);
      parser.parse(hwVersion(0xFD, 3, 4), 1000);

      parser.encodeRequest(GanRequest.hardware); // clears what was collected
      expect(parser.parse(hwVersion(0xFE, 1, 2), 1000), isEmpty);
    });
  });

  test('request and history messages are 20 bytes', () {
    final parser = newParser();
    for (final r in GanRequest.values) {
      expect(parser.encodeRequest(r), hasLength(20), reason: r.name);
    }
    expect(parser.encodeMoveHistory(9, 4), hasLength(20));
  });
}

/// Builds the payload of a Gen4 packet field by field.
class _Bits {
  final List<String> _bits;
  final int _bytes;

  _Bits(this._bytes) : _bits = List<String>.filled(_bytes * 8, '0');

  void put(int start, int length, int value) {
    final b = value.toRadixString(2).padLeft(length, '0');
    for (var i = 0; i < length; i++) {
      _bits[start + i] = b[i];
    }
  }

  void putLe(int start, int bytes, int value) {
    for (var i = 0; i < bytes; i++) {
      put(start + i * 8, 8, (value >> (i * 8)) & 0xFF);
    }
  }

  List<int> toBytes() {
    final s = _bits.join();
    return [
      for (var i = 0; i < _bytes; i++)
        int.parse(s.substring(i * 8, i * 8 + 8), radix: 2),
    ];
  }
}
