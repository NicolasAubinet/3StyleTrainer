import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/src/crypto/gan_cipher.dart';
import 'package:smartcube/src/cube/cubie_cube.dart';
import 'package:smartcube/src/drivers/gan_gen2_parser.dart';
import 'package:smartcube/src/drivers/gan_gen3_parser.dart';
import 'package:smartcube/src/drivers/gan_protocol.dart';
import 'package:smartcube/src/model/cube_move.dart';

void main() {
  const mac = 'CF:30:16:00:AB:CD';
  final cipher = GanCipher.forMac(
      GanGen2Parser.baseKey, GanGen2Parser.baseIv, GanCipher.macBytes(mac));

  GanGen3Parser newParser() => GanGen3Parser(GanCipher.macBytes(mac));

  const uFacelet = 'UUUUUUUUUBBBRRRRRRRRRFFFFFFDDDDDDDDDFFFLLLLLLLLLBBBBBB';

  /// Face codes as a live Gen3 move packet encodes them, in `URFDLB` order.
  const liveFaceCodes = [2, 32, 8, 1, 16, 4];

  /// Face codes as a move-history packet encodes them.
  const historyFaceCodes = [1, 5, 3, 0, 4, 2];

  // Command messages are 16 bytes, but the cube's own event packets are longer —
  // facelets alone reach bit 132.
  List<int> packet(void Function(_Bits) build) {
    final bits = _Bits(20);
    bits.put(0, 8, GanGen3Parser.magic);
    bits.put(16, 8, 1); // non-zero data length
    build(bits);
    return cipher.encode(bits.toBytes());
  }

  List<int> facelets(int serial) => packet((b) {
        b.put(8, 8, 0x02);
        b.putLe(24, 2, serial);
        for (var i = 0; i < 7; i++) {
          b.put(40 + i * 3, 3, i); // solved corner permutation
          b.put(61 + i * 2, 2, 0);
        }
        for (var i = 0; i < 11; i++) {
          b.put(77 + i * 4, 4, i); // solved edge permutation
          b.put(121 + i, 1, 0);
        }
      });

  List<int> movePacket(int serial, int faceIndex,
          {bool prime = false, int cubeTimeMs = 1000}) =>
      packet((b) {
        b.put(8, 8, 0x01);
        b.putLe(24, 4, cubeTimeMs);
        b.putLe(56, 2, serial);
        b.put(72, 2, prime ? 1 : 0);
        b.put(74, 6, liveFaceCodes[faceIndex]);
      });

  /// A history reply of [moves] (face index, prime), newest first from [startSerial].
  List<int> historyPacket(int startSerial, List<(int, bool)> moves) => packet((b) {
        b.put(8, 8, 0x06);
        b.put(16, 8, moves.length ~/ 2 + 1); // count = (dataLength - 1) * 2
        b.put(24, 8, startSerial);
        for (var i = 0; i < moves.length; i++) {
          b.put(32 + 4 * i, 3, historyFaceCodes[moves[i].$1]);
          b.put(35 + 4 * i, 1, moves[i].$2 ? 1 : 0);
        }
      });

  /// Facelets are only checked for gaps once moves have settled.
  int settled(int hostMs) => hostMs + 1000;

  test('a packet without the magic byte is ignored', () {
    final raw = cipher.encode(List<int>.filled(16, 0));
    expect(newParser().parse(raw, 1000), isEmpty);
  });

  test('battery packet decodes to level', () {
    final events = newParser().parse(
        packet((b) => b
          ..put(8, 8, 0x10)
          ..put(24, 8, 77)),
        1000);
    expect((events.single as GanBatteryEvent).level, 77);
  });

  test('hardware packet decodes name and versions', () {
    final events = newParser().parse(
        packet((b) {
          b.put(8, 8, 0x07);
          const name = 'i2   ';
          for (var i = 0; i < 5; i++) {
            b.put(32 + i * 8, 8, name.codeUnitAt(i));
          }
          b.put(72, 4, 3); // sw major
          b.put(76, 4, 4); // sw minor
          b.put(80, 4, 1); // hw major
          b.put(84, 4, 2); // hw minor
        }),
        1000);
    final e = events.single as GanInfoEvent;
    expect(e.hardwareName, 'i2');
    expect(e.hardwareVersion, '1.2');
    expect(e.softwareVersion, '3.4');
    expect(e.gyroSupported, isFalse);
  });

  test('facelets packet decodes the solved cube and anchors', () {
    final parser = newParser();
    final events = parser.parse(facelets(5), 1000);
    expect((events.single as GanStateEvent).state.facelets,
        CubieCube.solvedFacelet);
    expect(parser.needsAnchor, isFalse);
  });

  test('a move before any facelets anchor is ignored', () {
    expect(newParser().parse(movePacket(6, 0), 1000), isEmpty);
  });

  test('a move after an anchor yields the move and resulting state', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    final e = parser.parse(movePacket(6, 0), 1500).single as GanMoveEvent;

    expect(e.move.face, Face.U);
    expect(e.move.prime, isFalse);
    expect(e.stateAfter.facelets, uFacelet);
    expect(parser.currentState.facelets, uFacelet);
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
    final e = parser.parse(movePacket(6, 2, prime: true), 1500).single
        as GanMoveEvent;
    expect(e.move.face, Face.F);
    expect(e.move.prime, isTrue);
  });

  test('the cube clock is carried through', () {
    final parser = newParser();
    parser.parse(facelets(5), 1000);
    final e = parser.parse(movePacket(6, 0, cubeTimeMs: 1234), 1500).single
        as GanMoveEvent;
    expect(e.move.cubeTimestamp, const Duration(milliseconds: 1234));
  });

  group('gap recovery', () {
    test('a gap holds the move back and asks for history', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);

      // Serial 8 arrives while the model is at 5: 6 and 7 were never seen.
      final events = parser.parse(movePacket(8, 0), 1500);

      final request = events.single as GanHistoryRequestEvent;
      expect(request.serial, 8);
      expect(request.count, 3);
      // Nothing is applied out of order.
      expect(parser.currentState.facelets, CubieCube.solvedFacelet);
    });

    test('history fills the gap and everything replays in order', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      parser.parse(movePacket(8, 0), 1500); // gap: 6, 7 missing

      // History answers newest-first from serial 7: U at 7, U at 6.
      final events = parser.parse(historyPacket(7, [(0, false), (0, false)]), 1600);

      final moves = events.whereType<GanMoveEvent>().toList();
      expect(moves, hasLength(3)); // 6, 7, then the held-back 8
      expect(moves.every((m) => m.move.face == Face.U), isTrue);
      // Recovered moves carry no host time; the live one kept its own.
      expect(moves[0].move.hostTimestamp, isNull);
      expect(moves[1].move.hostTimestamp, isNull);
      expect(moves[2].move.hostTimestamp, isNotNull);
      // Three U turns from solved is one U anticlockwise.
      expect(parser.currentState.facelets,
          newParser().let((p) {
            p.parse(facelets(5), 1000);
            p.parse(movePacket(6, 0, prime: true), 1500);
            return p.currentState.facelets;
          }));
    });

    test('history that does not close the gap releases nothing', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      parser.parse(movePacket(9, 0), 1500); // 6, 7, 8 missing

      // Only serial 8 comes back: 6 and 7 are still missing.
      final events = parser.parse(historyPacket(8, [(0, false)]), 1600);

      expect(events.whereType<GanMoveEvent>(), isEmpty);
      expect(parser.currentState.facelets, CubieCube.solvedFacelet);
    });

    test('a duplicate history move is not applied twice', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      parser.parse(movePacket(8, 0), 1500);

      parser.parse(historyPacket(7, [(0, false), (0, false)]), 1600);
      final again = parser.parse(historyPacket(7, [(0, false), (0, false)]), 1700);

      expect(again.whereType<GanMoveEvent>(), isEmpty);
    });

    test('history moves outside the gap are ignored', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      parser.parse(movePacket(8, 0), 1500);

      // Serial 3 is behind the model — long since applied, not a missed move.
      final events = parser.parse(historyPacket(3, [(0, false), (0, false)]), 1600);
      expect(events.whereType<GanMoveEvent>(), isEmpty);
    });

    test('a runaway gap gives up and declares a desync', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);

      // Moves keep arriving while the gap at 6 never closes.
      final events = <GanEvent>[];
      for (var i = 0; i < 20; i++) {
        events.addAll(parser.parse(movePacket(10 + i, 0), 1500 + i));
      }

      expect(events.whereType<GanDesyncEvent>(), isNotEmpty);
      expect(parser.needsAnchor, isTrue);
      // And the cube's own facelets can bring it back.
      expect(parser.parse(facelets(40), 3000), hasLength(1));
      expect(parser.needsAnchor, isFalse);
    });
  });

  group('periodic facelets', () {
    test('a facelets level with the model is applied', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      parser.parse(movePacket(6, 0), 1500);
      expect(parser.parse(facelets(6), settled(1500)), hasLength(1));
    });

    test('a facelets running ahead of the model asks for the missed moves', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);

      // The cube says it is at serial 8; the model never saw 6, 7, 8.
      final events = parser.parse(facelets(8), settled(1000));

      final request = events.single as GanHistoryRequestEvent;
      expect(request.count, 4); // diff + 1
      expect(parser.currentState.facelets, CubieCube.solvedFacelet);
    });

    test('a facelets arriving mid-turn is left alone', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      parser.parse(movePacket(6, 0), 1500);

      // Still within the settle window: the model is meant to trail here.
      expect(parser.parse(facelets(8), 1600), isEmpty);
    });

    test('a stale facelets snapshot does not rewind the tracked model', () {
      final parser = newParser();
      parser.parse(facelets(5), 1000);
      parser.parse(movePacket(6, 0), 1500);

      // The cube answers with its state as of serial 5 — before that move.
      expect(parser.parse(facelets(5), settled(1500)), isEmpty);
      expect(parser.currentState.facelets, uFacelet);
    });
  });

  group('history window alignment', () {
    test('an even serial is pulled back to the odd one below it', () {
      expect(GanGen3Parser.alignHistoryWindow(8, 2), (7, 2));
    });

    test('an odd count is rounded up to an even one', () {
      expect(GanGen3Parser.alignHistoryWindow(9, 3), (9, 4));
    });

    test('the window never runs past the serial wrap', () {
      // Asking for more moves than have ever happened would come back spoofed.
      expect(GanGen3Parser.alignHistoryWindow(3, 8), (3, 4));
    });
  });

  test('the cube asking to disconnect is surfaced', () {
    final events = newParser().parse(packet((b) => b.put(8, 8, 0x11)), 1000);
    expect(events.single, isA<GanDisconnectEvent>());
  });

  test('reset and request messages are 16 bytes', () {
    final parser = newParser();
    for (final r in GanRequest.values) {
      expect(parser.encodeRequest(r), hasLength(16), reason: r.name);
    }
    expect(parser.encodeMoveHistory(9, 4), hasLength(16));
  });
}

/// Builds the payload of a Gen3 packet field by field.
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

  /// Little-endian multi-byte field.
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

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
