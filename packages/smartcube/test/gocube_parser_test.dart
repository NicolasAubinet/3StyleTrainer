import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/src/cube/cubie_cube.dart';
import 'package:smartcube/src/drivers/gocube_parser.dart';
import 'package:smartcube/src/model/cube_move.dart';

/// All packets are synthetic — no GoCube hardware exists here (§29). They are
/// built from the same csTimer mapping tables the parser ports, so a mismatch
/// fails the test rather than passing on a shared mistake would require both to
/// be wrong the same way.
void main() {
  // Mirror of the parser's private tables, used to *build* packets here.
  const axisPerm = [5, 2, 0, 3, 1, 4];
  const facePerm = [0, 1, 2, 5, 8, 7, 6, 3];
  const faceOffset = [0, 0, 6, 2, 0, 0];
  const colours = 'BFUDRL';

  // The solved facelet after a single U turn (shared with the MoYu test).
  const uFacelet = 'UUUUUUUUUBBBRRRRRRRRRFFFFFFDDDDDDDDDFFFLLLLLLLLLBBBBBB';

  /// Frame a message body the way the cube does: `2a · len · type · data · crc ·
  /// 0d · 0a`. The parser ignores len and crc, so 0s are fine there.
  List<int> frame(int type, List<int> data) =>
      [0x2a, data.length, type, ...data, 0x00, 0x0d, 0x0a];

  /// A one-move packet. `b` is the raw move byte (`code << 1 | dir`).
  List<int> movePacket(int b) => frame(GoCubeParser.msgMove, [b, 0]);

  /// Inverse of the parser's state decode: turn a 54-char URFDLB facelet into the
  /// 54 colour-coded state bytes the cube would send for it.
  List<int> stateData(String facelet) {
    final data = List<int>.filled(54, 0);
    for (var a = 0; a < 6; a++) {
      final base = axisPerm[a] * 9;
      final aoff = faceOffset[a];
      data[a * 9] = colours.indexOf(facelet[base + 4]);
      for (var i = 0; i < 8; i++) {
        data[a * 9 + i + 1] =
            colours.indexOf(facelet[base + facePerm[(i + aoff) % 8]]);
      }
    }
    return data;
  }

  List<int> statePacket(String facelet) =>
      frame(GoCubeParser.msgState, stateData(facelet));

  test('battery packet decodes to level', () {
    final events = GoCubeParser().parse(frame(GoCubeParser.msgBattery, [77]), 0);
    expect((events.single as GoCubeBatteryEvent).level, 77);
  });

  test('a solved state packet anchors the model', () {
    final parser = GoCubeParser();
    expect(parser.needsAnchor, isTrue);
    final events = parser.parse(statePacket(CubieCube.solvedFacelet), 0);
    final e = events.single as GoCubeStateEvent;
    expect(e.state.facelets, CubieCube.solvedFacelet);
    expect(e.isResync, isFalse);
    expect(parser.needsAnchor, isFalse);
  });

  test('a scrambled state round-trips through facePerm/faceOffset', () {
    // Exercises the perimeter mapping — a solved state would pass even if it were
    // wrong, since every sticker on a face is identical.
    final parser = GoCubeParser();
    final e = parser.parse(statePacket(uFacelet), 0).single as GoCubeStateEvent;
    expect(e.state.facelets, uFacelet);
  });

  test('a move before any anchor is dropped', () {
    expect(GoCubeParser().parse(movePacket(4), 0), isEmpty);
  });

  test('a U move after anchor yields the move and the resulting state', () {
    final parser = GoCubeParser();
    parser.parse(statePacket(CubieCube.solvedFacelet), 0);
    final e = parser.parse(movePacket(4), 100).single as GoCubeMoveEvent;
    expect(e.move.face, Face.U);
    expect(e.move.prime, isFalse);
    expect(e.stateAfter.facelets, uFacelet);
    expect(parser.currentState.facelets, uFacelet);
  });

  test('every move byte maps to the documented face and direction', () {
    // b = code << 1 | dir, code indexes the cube's own face order.
    const expected = {
      4: (Face.U, false), 5: (Face.U, true),
      8: (Face.R, false), 9: (Face.R, true),
      2: (Face.F, false), 3: (Face.F, true),
      6: (Face.D, false), 7: (Face.D, true),
      10: (Face.L, false), 11: (Face.L, true),
      0: (Face.B, false), 1: (Face.B, true),
    };
    expected.forEach((b, want) {
      final parser = GoCubeParser()
        ..parse(statePacket(CubieCube.solvedFacelet), 0);
      final e = parser.parse(movePacket(b), 0).single as GoCubeMoveEvent;
      expect((e.move.face, e.move.prime), want, reason: 'byte $b');
    });
  });

  test('a packet carrying several moves emits them in order', () {
    final parser = GoCubeParser()
      ..parse(statePacket(CubieCube.solvedFacelet), 0);
    // U then U' — back to solved.
    final events = parser.parse(frame(GoCubeParser.msgMove, [4, 0, 5, 0]), 0);
    expect(events, hasLength(2));
    expect((events[0] as GoCubeMoveEvent).move.notation, 'U');
    expect((events[1] as GoCubeMoveEvent).move.notation, "U'");
    // Only the most recent move of a packet carries a host timestamp.
    expect((events[0] as GoCubeMoveEvent).move.hostTimestamp, isNull);
    expect((events[1] as GoCubeMoveEvent).move.hostTimestamp, isNotNull);
    expect(parser.currentState.facelets, CubieCube.solvedFacelet);
  });

  test('a state that changes an anchored model is flagged a resync', () {
    final parser = GoCubeParser()
      ..parse(statePacket(CubieCube.solvedFacelet), 0);
    // A state disagreeing with the tracked model → moves were lost.
    final changed = parser.parse(statePacket(uFacelet), 0).single;
    expect((changed as GoCubeStateEvent).isResync, isTrue);
    // Re-stating the same thing is not a resync.
    final same = parser.parse(statePacket(uFacelet), 0).single;
    expect((same as GoCubeStateEvent).isResync, isFalse);
  });

  test('a corrupt move byte stops the packet but keeps valid moves', () {
    final parser = GoCubeParser()
      ..parse(statePacket(CubieCube.solvedFacelet), 0);
    // First move valid (U), second byte's code (200 >> 1 = 100) is out of range.
    final events = parser.parse(frame(GoCubeParser.msgMove, [4, 0, 200, 0]), 0);
    expect(events, hasLength(1));
    expect((events.single as GoCubeMoveEvent).move.face, Face.U);
  });

  group('framing', () {
    test('a too-short packet is dropped', () {
      expect(GoCubeParser().parse([0x2a, 0, 5, 0x0d], 0), isEmpty);
    });
    test('a wrong prefix is dropped', () {
      expect(GoCubeParser().parse([0x00, 1, 5, 77, 0, 0x0d, 0x0a], 0), isEmpty);
    });
    test('a missing terminator is dropped', () {
      expect(GoCubeParser().parse([0x2a, 1, 5, 77, 0, 0x00, 0x00], 0), isEmpty);
    });
    test('an unknown message type is ignored', () {
      expect(GoCubeParser().parse(frame(3, [1, 2, 3, 4]), 0), isEmpty);
    });
  });
}
