import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/src/crypto/gan_cipher.dart';
import 'package:smartcube/src/cube/cubie_cube.dart';
import 'package:smartcube/src/drivers/moyu_v10_parser.dart';
import 'package:smartcube/src/model/cube_move.dart';

void main() {
  // Encrypted packets built by csTimer's cipher for MAC CF:30:16:00:AB:CD:
  //   c164 = battery level 77
  //   c163 = solved cube, move counter 5
  //   c165 = one move (U), move counter 6, dt=500ms
  const c164 = [183, 222, 38, 107, 141, 80, 66, 141, 196, 87, 86, 24, 165, 186, 206, 194, 224, 45, 123, 22];
  const c163 = [20, 81, 108, 156, 152, 10, 152, 58, 229, 121, 98, 221, 11, 123, 49, 53, 221, 107, 154, 186];
  const c165 = [223, 209, 150, 204, 116, 21, 65, 40, 149, 201, 145, 0, 11, 185, 99, 221, 222, 17, 54, 129];

  const uFacelet = 'UUUUUUUUUBBBRRRRRRRRRFFFFFFDDDDDDDDDFFFLLLLLLLLLBBBBBB';

  MoyuV10Parser newParser() =>
      MoyuV10Parser(GanCipher.macBytes('CF:30:16:00:AB:CD'));

  test('battery packet decodes to level', () {
    final events = newParser().parse(c164, 1000);
    expect(events, hasLength(1));
    expect((events.single as MoyuBatteryEvent).level, 77);
  });

  test('state packet decodes to the solved cube and anchors', () {
    final events = newParser().parse(c163, 1000);
    expect(events, hasLength(1));
    expect((events.single as MoyuStateEvent).state.facelets,
        CubieCube.solvedFacelet);
  });

  test('a state packet decrypted with the wrong MAC does not anchor', () {
    // The V11 shares the V10's name family but not its OUI, so the name-derived
    // MAC can be one byte off. Garbage must not pass for a cube state, or the
    // driver reports ready and then never sees a move.
    final wrongKey = MoyuV10Parser(GanCipher.macBytes('CF:30:16:02:52:88'));
    expect(wrongKey.parse(c163, 1000), isEmpty);
    expect(wrongKey.needsAnchor, isTrue);
  });

  test('move packet after a state anchor yields the move and resulting state', () {
    final parser = newParser();
    parser.parse(c163, 1000); // anchor at solved, moveCnt 5
    final events = parser.parse(c165, 1500); // one U move, moveCnt 6

    expect(events, hasLength(1));
    final e = events.single as MoyuMoveEvent;
    expect(e.move.face, Face.U);
    expect(e.move.prime, isFalse);
    expect(e.stateAfter.facelets, uFacelet);
    expect(parser.currentState.facelets, uFacelet);
  });

  test('a move before any state anchor is ignored', () {
    // No 163 first → prevMoveCnt still -1 → move dropped.
    expect(newParser().parse(c165, 1000), isEmpty);
  });

  test('resetAnchor lets a later state packet re-anchor', () {
    final parser = newParser();
    parser.parse(c163, 1000);
    expect(parser.parse(c163, 1100), isEmpty); // already anchored → ignored
    parser.resetAnchor();
    expect(parser.parse(c163, 1200), hasLength(1)); // re-anchors
  });

  // A move packet carries only the last 5 moves, so a counter that ran further
  // ahead than that means notifications were missed (radio drop / cube waking).
  final cipher = GanCipher.forMac(MoyuV10Parser.baseKey, MoyuV10Parser.baseIv,
      GanCipher.macBytes('CF:30:16:00:AB:CD'));
  List<int> movePacket(int moveCnt, {List<int> moves = const [4, 4, 4, 4, 4]}) {
    final bits = StringBuffer()..write(_bin(165, 8));
    for (var i = 0; i < 5; i++) {
      bits.write(_bin(100, 16)); // timestamps
    }
    bits.write(_bin(moveCnt, 8));
    for (final m in moves) {
      bits.write(_bin(m, 5));
    }
    final s = bits.toString().padRight(160, '0');
    return cipher.encode([
      for (var i = 0; i < 20; i++) int.parse(s.substring(i * 8, i * 8 + 8), radix: 2),
    ]);
  }

  test('more moves than a packet carries declares a desync, applying none', () {
    final parser = newParser();
    parser.parse(c163, 1000); // anchor at solved, moveCnt 5

    // The cube reports counter 12: seven moves happened, only five are in hand.
    final events = parser.parse(movePacket(12), 1500);

    expect(events, hasLength(1));
    expect((events.single as MoyuDesyncEvent).lostMoves, 2);
    // Nothing is applied — a partial replay would leave the model silently wrong.
    expect(parser.currentState.facelets, CubieCube.solvedFacelet);
    expect(parser.needsAnchor, isTrue);
  });

  test('moves stay ignored after a desync until a state packet re-anchors', () {
    final parser = newParser();
    parser.parse(c163, 1000);
    parser.parse(movePacket(12), 1500); // desync

    expect(parser.parse(movePacket(13, moves: [4, 4, 4, 4, 4]), 1600), isEmpty);
    expect(parser.currentState.facelets, CubieCube.solvedFacelet);

    // The cube's own state is authoritative; tracking resumes from it.
    expect(parser.parse(c163, 1700), hasLength(1));
    expect(parser.needsAnchor, isFalse);
    expect(parser.parse(c165, 1800), hasLength(1)); // moveCnt 6 — tracking again
    expect(parser.currentState.facelets, uFacelet);
  });

  test('requestPull re-anchors an anchored model without losing moves', () {
    final parser = newParser();
    parser.parse(c163, 1000);
    parser.requestPull();

    // A move landing while the pull is in flight is still tracked...
    expect(parser.parse(c165, 1100), hasLength(1));
    // ...and the state answer is accepted even though the model was anchored.
    expect(parser.parse(c163, 1200), hasLength(1));
    expect(parser.currentState.facelets, CubieCube.solvedFacelet);
  });
}

String _bin(int value, int width) => value.toRadixString(2).padLeft(width, '0');
