import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/src/crypto/gan_cipher.dart';
import 'package:smartcube/src/cube/cubie_cube.dart';
import 'package:smartcube/src/driver.dart';
import 'package:smartcube/src/drivers/gan_driver.dart';
import 'package:smartcube/src/drivers/gan_gen2_parser.dart';
import 'package:smartcube/src/drivers/gan_protocol.dart';
import 'package:smartcube/src/model/cube_move.dart';

void main() {
  const mac = 'CF:30:16:00:AB:CD';
  final cipher = GanCipher.forMac(
      GanGen2Parser.baseKey, GanGen2Parser.baseIv, GanCipher.macBytes(mac));

  GanGen2Parser newParser() => GanGen2Parser(GanCipher.macBytes(mac));

  const uFacelet = 'UUUUUUUUUBBBRRRRRRRRRFFFFFFDDDDDDDDDFFFLLLLLLLLLBBBBBB';

  /// A 20-byte Gen2 packet, encrypted the way the cube would send it.
  List<int> packet(void Function(_Bits) build) {
    final bits = _Bits();
    build(bits);
    return cipher.encode(bits.toBytes());
  }

  List<int> facelets(int serial, {List<int>? cp, List<int>? co}) {
    final cpv = cp ?? List<int>.generate(8, (i) => i);
    final cov = co ?? List<int>.filled(8, 0);
    return packet((b) {
      b.put(0, 4, 0x04);
      b.put(4, 8, serial);
      for (var i = 0; i < 7; i++) {
        b.put(12 + i * 3, 3, cpv[i]);
        b.put(33 + i * 2, 2, cov[i]);
      }
      for (var i = 0; i < 11; i++) {
        b.put(47 + i * 4, 4, i); // solved edge permutation
        b.put(91 + i, 1, 0);
      }
    });
  }

  /// [moves] are `(face, prime)` newest-first, as the cube packs them.
  List<int> movePacket(int serial, List<(int, bool)> moves, {int elapsed = 500}) {
    return packet((b) {
      b.put(0, 4, 0x02);
      b.put(4, 8, serial);
      for (var i = 0; i < moves.length; i++) {
        b.put(12 + 5 * i, 4, moves[i].$1);
        b.put(16 + 5 * i, 1, moves[i].$2 ? 1 : 0);
        b.put(47 + 16 * i, 16, elapsed);
      }
    });
  }

  test('battery packet decodes to level', () {
    final events = newParser().parse(
        packet((b) => b
          ..put(0, 4, 0x09)
          ..put(8, 8, 77)),
        1000);
    expect((events.single as GanBatteryEvent).level, 77);
  });

  test('battery level is clamped to 100', () {
    final events = newParser().parse(
        packet((b) => b
          ..put(0, 4, 0x09)
          ..put(8, 8, 255)),
        1000);
    expect((events.single as GanBatteryEvent).level, 100);
  });

  test('hardware packet decodes name and versions', () {
    final events = newParser().parse(
        packet((b) {
          b.put(0, 4, 0x05);
          b.put(8, 8, 1); // hw major
          b.put(16, 8, 2); // hw minor
          b.put(24, 8, 3); // sw major
          b.put(32, 8, 4); // sw minor
          const name = 'GAN356i3';
          for (var i = 0; i < 8; i++) {
            b.put(40 + i * 8, 8, name.codeUnitAt(i));
          }
          b.put(104, 1, 1); // gyro supported
        }),
        1000);
    final e = events.single as GanInfoEvent;
    expect(e.hardwareName, 'GAN356i3');
    expect(e.hardwareVersion, '1.2');
    expect(e.softwareVersion, '3.4');
    expect(e.gyroSupported, isTrue);
  });

  test('facelets packet decodes the solved cube and anchors', () {
    final parser = newParser();
    final events = parser.parse(facelets(5), 1000);
    expect((events.single as GanStateEvent).state.facelets,
        CubieCube.solvedFacelet);
    expect(parser.needsAnchor, isFalse);
  });

  test('facelets derive the eighth corner and twelfth edge from the checksum', () {
    // Only 7 corners are sent. Twist the first two so the checksum has to put
    // the eighth corner back at orientation 1 for the sum to be a multiple of 3.
    final parser = newParser();
    final events = parser.parse(
        facelets(5, co: [1, 1, 0, 0, 0, 0, 0, 0]),
        1000);
    expect(events, hasLength(1));
    // A cube where only corner twists differ is still structurally valid.
    expect(parser.currentState.facelets, isNot(CubieCube.solvedFacelet));
  });

  test('a corrupt facelets packet is dropped, not applied', () {
    // Corner permutation with a duplicate makes the derived eighth corner fall
    // outside 0..7, so the packet cannot describe a real cube.
    final parser = newParser();
    expect(parser.parse(facelets(5, cp: [0, 0, 0, 0, 0, 0, 0, 0]), 1000), isEmpty);
    expect(parser.needsAnchor, isTrue);
  });

  test('move packet after an anchor yields the move and resulting state', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    final events = parser.parse(movePacket(6, [(0, false)]), 1500);

    final e = events.single as GanMoveEvent;
    expect(e.move.face, Face.U);
    expect(e.move.prime, isFalse);
    expect(e.stateAfter.facelets, uFacelet);
    expect(parser.currentState.facelets, uFacelet);
  });

  test('a prime move decodes with the direction bit set', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    final e = parser.parse(movePacket(6, [(2, true)]), 1500).single
        as GanMoveEvent;
    expect(e.move.face, Face.F);
    expect(e.move.prime, isTrue);
  });

  test('a move before any facelets anchor is ignored', () {
    expect(newParser().parse(movePacket(6, [(0, false)]), 1000), isEmpty);
  });

  test('recovered moves replay oldest-first and only the newest carries host time',
      () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    // Serial jumps by 2: the packet holds both, newest at index 0.
    final events = parser.parse(movePacket(7, [(0, false), (0, false)]), 1500);

    expect(events, hasLength(2));
    final first = events[0] as GanMoveEvent;
    final second = events[1] as GanMoveEvent;
    expect(first.move.hostTimestamp, isNull); // recovered, never seen live
    expect(second.move.hostTimestamp, isNotNull);
    expect(second.move.cubeTimestamp, greaterThan(first.move.cubeTimestamp));
    // Two U turns from solved.
    expect(parser.currentState.facelets, isNot(uFacelet));
  });

  test('more moves than a packet carries declares a desync, applying none', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);

    // Serial 14 is 9 moves on from 5, but a packet holds only 7.
    final events = parser.parse(movePacket(14, [(0, false)]), 1500);

    expect((events.single as GanDesyncEvent).lostMoves, 2);
    expect(parser.currentState.facelets, CubieCube.solvedFacelet);
    expect(parser.needsAnchor, isTrue);
  });

  test('moves stay ignored after a desync until facelets re-anchor', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    parser.parse(movePacket(14, [(0, false)]), 1500); // desync

    expect(parser.parse(movePacket(15, [(0, false)]), 1600), isEmpty);
    expect(parser.currentState.facelets, CubieCube.solvedFacelet);

    expect(parser.parse(facelets(15), 1700), hasLength(1));
    expect(parser.needsAnchor, isFalse);
    expect(parser.parse(movePacket(16, [(0, false)]), 1800), hasLength(1));
    expect(parser.currentState.facelets, uFacelet);
  });

  test('a repeated serial reports no moves', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    expect(parser.parse(movePacket(5, [(0, false)]), 1500), isEmpty);
  });

  test('a stale facelets snapshot does not rewind the tracked model', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    parser.parse(movePacket(6, [(0, false)]), 1500); // now at serial 6

    // The cube answers a pull with its state as of serial 5 — before that move.
    expect(parser.parse(facelets(5), 1600), isEmpty);
    expect(parser.currentState.facelets, uFacelet);
  });

  test('a facelets snapshot at the current serial is accepted', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    parser.parse(movePacket(6, [(0, false)]), 1500);
    expect(parser.parse(facelets(6), 1600), hasLength(1));
  });

  test('the cube asking to disconnect is surfaced', () {
    final events = newParser().parse(packet((b) => b.put(0, 4, 0x0D)), 1000);
    expect(events.single, isA<GanDisconnectEvent>());
  });

  test('the gyro stream is dropped', () {
    expect(newParser().parse(packet((b) => b.put(0, 4, 0x01)), 1000), isEmpty);
  });

  group('MAC derivation', () {
    CubeAdvertisement adv(Map<int, List<int>> manufacturerData) =>
        CubeAdvertisement(
            id: 'x', name: 'GAN356i3', manufacturerData: manufacturerData);

    test('reads the MAC from the last six bytes of GAN manufacturer data', () {
      expect(
        GanDriver.deriveMac(adv({
          0x0001: [0, 0, 0, 0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56],
        })),
        '56:34:12:EF:CD:AB',
      );
    });

    test('accepts any GAN company identifier', () {
      expect(
        GanDriver.deriveMac(adv({
          0xFF01: [0, 0, 0, 0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56],
        })),
        '56:34:12:EF:CD:AB',
      );
    });

    test('ignores manufacturer data from other vendors', () {
      expect(GanDriver.deriveMac(adv({0x004C: [0, 0, 0, 1, 2, 3, 4, 5, 6]})),
          isNull);
    });

    test('reads only the first nine bytes when more are advertised', () {
      expect(
        GanDriver.deriveMac(adv({
          0x0001: [0, 0, 0, 0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56, 0x99, 0x99],
        })),
        '56:34:12:EF:CD:AB',
      );
    });

    test('is absent when the platform hides manufacturer data', () {
      expect(GanDriver.deriveMac(adv(const {})), isNull);
      expect(GanDriver().needsExplicitMac(adv(const {})), isTrue);
    });
  });

  group('advertisement matching', () {
    test('claims GAN, MG and AiCube names', () {
      for (final name in ['GAN356i3', 'MG3Ai', 'AiCube v1']) {
        expect(
            GanDriver().matches(CubeAdvertisement(id: 'x', name: name)), isTrue,
            reason: name);
      }
    });

    test('claims a nameless device by Gen2 service', () {
      expect(
          GanDriver().matches(CubeAdvertisement(
              id: 'x', serviceUuids: [GanDriver.gen2Service])),
          isTrue);
    });

    test('does not claim the MoYu V10', () {
      expect(
          GanDriver().matches(CubeAdvertisement(id: 'x', name: 'WCU_MY32_ABCD')),
          isFalse);
    });
  });
}

/// Builds the 160-bit payload of a Gen2 packet field by field.
class _Bits {
  final List<String> _bits = List<String>.filled(160, '0');

  void put(int start, int length, int value) {
    final b = value.toRadixString(2).padLeft(length, '0');
    for (var i = 0; i < length; i++) {
      _bits[start + i] = b[i];
    }
  }

  List<int> toBytes() {
    final s = _bits.join();
    return [
      for (var i = 0; i < 20; i++)
        int.parse(s.substring(i * 8, i * 8 + 8), radix: 2),
    ];
  }
}
