import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
import 'package:smartcube/src/drivers/giiker_parser.dart';

/// Packets are synthesised by inverting the decoder: a facelet string is
/// brute-forced back into Giiker's cubie nibbles through the same facelet
/// tables the parser decodes with, so any state [CubieCube] can produce is
/// encodable. No hardware capture exists yet — these are synthetic fixtures.
void main() {
  const coMask = [-1, 1, -1, 1, 1, -1, 1, -1];
  const key = GiikerParser.decryptKey;

  String colour(int home) => 'URFDLB'[home ~/ 9];

  /// Nibbles 0..31: cubie state in Giiker piece ordering.
  List<int> stateNibbles(String facelets) {
    final hex = List<int>.filled(32, 0);
    for (var g = 0; g < 8; g++) {
      for (var p = 0; p < 8; p++) {
        for (var o = 0; o < 3; o++) {
          var ok = true;
          for (var n = 0; n < 3 && ok; n++) {
            ok = facelets[GiikerParser.cFacelet[g][(n + o) % 3]] ==
                colour(GiikerParser.cFacelet[p][n]);
          }
          if (ok) {
            hex[g] = p + 1;
            hex[g + 8] = coMask[g] == 1 ? o : (3 - o) % 3;
          }
        }
      }
    }
    for (var g = 0; g < 12; g++) {
      for (var p = 0; p < 12; p++) {
        for (var o = 0; o < 2; o++) {
          var ok = true;
          for (var n = 0; n < 2 && ok; n++) {
            ok = facelets[GiikerParser.eFacelet[g][(n + o) % 2]] ==
                colour(GiikerParser.eFacelet[p][n]);
          }
          if (ok) {
            hex[16 + g] = p + 1;
            if (o == 1) hex[28 + g ~/ 4] |= 1 << (3 - g % 4);
          }
        }
      }
    }
    return hex;
  }

  List<int> toBytes(List<int> nibbles) => [
        for (var i = 0; i < nibbles.length; i += 2)
          nibbles[i] << 4 | nibbles[i + 1],
      ];

  /// A plain 20-byte packet: state + move history (newest first, padded with
  /// valid dummy entries the way a real cube's rolling history is populated).
  List<int> packet(String facelets, List<(int, int)> history) {
    final hex = [...stateNibbles(facelets)];
    for (var k = 0; k < 4; k++) {
      final (face, dir) = k < history.length ? history[k] : (1, 1);
      hex.addAll([face, dir]);
    }
    return toBytes(hex);
  }

  /// The encrypted variant: 18 content bytes (two history entries) with the
  /// additive key subtracted, then the 0xA7 marker and the key-offset byte.
  List<int> encryptedPacket(String facelets, List<(int, int)> history) {
    const k1 = 3, k2 = 5;
    final plain = toBytes([
      ...stateNibbles(facelets),
      for (var k = 0; k < 2; k++) ...[
        k < history.length ? history[k].$1 : 1,
        k < history.length ? history[k].$2 : 1,
      ],
    ]);
    return [
      for (var i = 0; i < 18; i++) (plain[i] - key[i + k1] - key[i + k2]) & 0xff,
      0xa7,
      k1 << 4 | k2,
    ];
  }

  String afterMoves(List<(Face, bool)> moves, [String? from]) {
    final c = CubieCube();
    if (from != null) c.fromFacelet(from);
    for (final (face, prime) in moves) {
      c.applyMove(face, prime);
    }
    return c.toFaceCube();
  }

  test('the synthetic encoder inverts the decoder', () {
    final scrambled = afterMoves(const [
      (Face.R, false), (Face.U, true), (Face.F, false), //
      (Face.D, false), (Face.L, true), (Face.B, false),
    ]);
    final p = GiikerParser()..parse(packet(scrambled, const []), 0);
    expect(p.currentState.facelets, scrambled);
  });

  test('the first packet anchors without emitting moves', () {
    final p = GiikerParser();
    expect(p.needsAnchor, isTrue);
    final events = p.parse(packet(CubieCube.solvedFacelet, const [(4, 1)]), 0);
    expect(events, hasLength(1));
    expect((events.single as GiikerStateEvent).isResync, isFalse);
    expect(p.needsAnchor, isFalse);
    expect(p.currentState, CubeState.solved);
  });

  test('a turn decodes from the history against the packet state', () {
    final p = GiikerParser()..parse(packet(CubieCube.solvedFacelet, const []), 0);
    final afterU = afterMoves(const [(Face.U, false)]);
    final events = p.parse(packet(afterU, const [(4, 1)]), 100);
    final move = (events.single as GiikerMoveEvent).move;
    expect(move.face, Face.U);
    expect(move.prime, isFalse);
    expect(move.hostTimestamp, isNotNull);
    expect(p.currentState.facelets, afterU);
  });

  test("dir 3 is a prime turn", () {
    final p = GiikerParser()..parse(packet(CubieCube.solvedFacelet, const []), 0);
    final afterR3 = afterMoves(const [(Face.R, true)]);
    final events = p.parse(packet(afterR3, const [(5, 3)]), 0);
    final move = (events.single as GiikerMoveEvent).move;
    expect(move.face, Face.R);
    expect(move.prime, isTrue);
  });

  test('dir 2 expands to two quarter turns', () {
    final p = GiikerParser()..parse(packet(CubieCube.solvedFacelet, const []), 0);
    final afterU2 = afterMoves(const [(Face.U, false), (Face.U, false)]);
    final events = p.parse(packet(afterU2, const [(4, 2)]), 0);
    expect(events, hasLength(2));
    for (final e in events) {
      expect((e as GiikerMoveEvent).move.face, Face.U);
    }
    expect(p.currentState.facelets, afterU2);
  });

  test('a missed notification is healed from the move history', () {
    final p = GiikerParser()..parse(packet(CubieCube.solvedFacelet, const []), 0);
    // The U packet was lost; the R packet still carries U in its history.
    final afterUR = afterMoves(const [(Face.U, false), (Face.R, false)]);
    final events = p.parse(packet(afterUR, const [(5, 1), (4, 1)]), 200);
    expect(events, hasLength(2));
    final first = (events[0] as GiikerMoveEvent).move;
    final second = (events[1] as GiikerMoveEvent).move;
    expect(first.face, Face.U);
    expect(first.hostTimestamp, isNull);
    expect(second.face, Face.R);
    expect(second.hostTimestamp, isNotNull);
    expect(p.currentState.facelets, afterUR);
  });

  test('an unexplainable state becomes a resync and retracks', () {
    final p = GiikerParser()..parse(packet(CubieCube.solvedFacelet, const []), 0);
    final far = afterMoves(const [(Face.L, false), (Face.F, false)]);
    final events = p.parse(packet(far, const []), 0); // history: all dummy B's
    final e = events.single as GiikerStateEvent;
    expect(e.isResync, isTrue);
    expect(e.state.facelets, far);
    expect(p.currentState.facelets, far);
  });

  test('a duplicate packet emits nothing', () {
    final p = GiikerParser();
    final afterU = packet(afterMoves(const [(Face.U, false)]), const [(4, 1)]);
    p.parse(packet(CubieCube.solvedFacelet, const []), 0);
    expect(p.parse(afterU, 0), isNotEmpty);
    expect(p.parse(afterU, 0), isEmpty);
  });

  test('an encrypted packet decodes like a plain one', () {
    final p = GiikerParser();
    p.parse(encryptedPacket(CubieCube.solvedFacelet, const []), 0);
    expect(p.currentState, CubeState.solved);
    final afterF = afterMoves(const [(Face.F, false)]);
    final events = p.parse(encryptedPacket(afterF, const [(6, 1)]), 0);
    final move = (events.single as GiikerMoveEvent).move;
    expect(move.face, Face.F);
    expect(p.currentState.facelets, afterF);
  });

  test('corrupt packets are dropped', () {
    final p = GiikerParser();
    p.parse(packet(CubieCube.solvedFacelet, const []), 0);
    final bad = packet(CubieCube.solvedFacelet, const []);
    bad[0] = 0x00; // corner permutation nibble 0 is out of range
    expect(p.parse(bad, 0), isEmpty);
    expect(p.parse(const [1, 2, 3], 0), isEmpty); // truncated
    expect(p.currentState, CubeState.solved);
  });
}
