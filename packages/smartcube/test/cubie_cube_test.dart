import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/src/cube/cubie_cube.dart';
import 'package:smartcube/src/model/cube_move.dart';

const _faceByChar = {
  'U': Face.U,
  'R': Face.R,
  'F': Face.F,
  'D': Face.D,
  'L': Face.L,
  'B': Face.B,
};

/// Apply a WCA-notation scramble to a fresh solved cube via [CubieCube.applyMove].
CubieCube scramble(String seq) {
  final c = CubieCube();
  for (final mv in seq.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty)) {
    final face = _faceByChar[mv[0]]!;
    if (mv.length == 1) {
      c.applyMove(face, false);
    } else if (mv[1] == "'") {
      c.applyMove(face, true);
    } else if (mv[1] == '2') {
      c.applyMove(face, false);
      c.applyMove(face, false);
    }
  }
  return c;
}

void main() {
  // Reference facelets generated from csTimer's own mathlib.CubieCube (the
  // source we ported), so these pin our port to the reference implementation.
  const vectors = {
    '': CubieCube.solvedFacelet,
    'U': 'UUUUUUUUUBBBRRRRRRRRRFFFFFFDDDDDDDDDFFFLLLLLLLLLBBBBBB',
    'R': 'UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB',
    'F': 'UUUUUULLLURRURRURRFFFFFFFFFRRRDDDDDDLLDLLDLLDBBBBBBBBB',
    'D': 'UUUUUUUUURRRRRRFFFFFFFFFLLLDDDDDDDDDLLLLLLBBBBBBBBBRRR',
    'L': 'BUUBUUBUURRRRRRRRRUFFUFFUFFFDDFDDFDDLLLLLLLLLBBDBBDBBD',
    'B': 'RRRUUUUUURRDRRDRRDFFFFFFFFFDDDDDDLLLULLULLULLBBBBBBBBB',
    "U'": 'UUUUUUUUUFFFRRRRRRLLLFFFFFFDDDDDDDDDBBBLLLLLLRRRBBBBBB',
    "R'": 'UUBUUBUUBRRRRRRRRRFFUFFUFFUDDFDDFDDFLLLLLLLLLDBBDBBDBB',
    'B2': 'DDDUUUUUURRLRRLRRLFFFFFFFFFDDDDDDUUURLLRLLRLLBBBBBBBBB',
    // superflip: all edges flipped, corners solved.
    'U R2 F B R B2 R U2 L B2 R U\' D\' R2 F R\' L B2 U2 F2':
        'UBULURUFURURFRBRDRFUFLFRFDFDFDLDRDBDLULBLFLDLBUBRBLBDB',
    'R U2 F\' L D B2 R\' U L2 F D\' B U R\' F2 L2 D2 R2 U':
        'RLLFUDFRRUBDFRBBRLRUBLFUUFRLRDLDDLBBFDDLLBFDBFUUUBFDRU',
  };

  group('toFaceCube against csTimer reference vectors', () {
    vectors.forEach((seq, expected) {
      test('"${seq.isEmpty ? "(solved)" : seq}"', () {
        expect(scramble(seq).toFaceCube(), expected);
      });
    });
  });

  test('solved cube', () {
    final c = CubieCube();
    expect(c.isSolved, isTrue);
    expect(c.toFaceCube(), CubieCube.solvedFacelet);
  });

  test('a quarter turn and its inverse cancel', () {
    for (final f in Face.values) {
      final c = CubieCube()
        ..applyMove(f, false)
        ..applyMove(f, true);
      expect(c.isSolved, isTrue, reason: '$f then ${f}prime');
    }
  });

  test('a quarter turn has order 4', () {
    for (final f in Face.values) {
      final c = CubieCube();
      for (var i = 0; i < 4; i++) {
        c.applyMove(f, false);
      }
      expect(c.isSolved, isTrue, reason: '$f x4');
    }
  });

  test('sexy move x6 returns to solved', () {
    final c = CubieCube();
    for (var i = 0; i < 6; i++) {
      c
        ..applyMove(Face.R, false)
        ..applyMove(Face.U, false)
        ..applyMove(Face.R, true)
        ..applyMove(Face.U, true);
    }
    expect(c.isSolved, isTrue);
    expect(c.toFaceCube(), CubieCube.solvedFacelet);
  });

  test('fromFacelet round-trips through toFaceCube', () {
    for (final facelet in vectors.values) {
      final c = CubieCube();
      expect(c.fromFacelet(facelet), isTrue);
      expect(c.toFaceCube(), facelet);
    }
  });

  test('fromFacelet reconstructs the same permutation as move application', () {
    final scrambled = scramble("R U2 F' L D B2 R' U L2 F");
    final parsed = CubieCube()..fromFacelet(scrambled.toFaceCube());
    expect(parsed, scrambled);
  });

  test('fromFacelet rejects invalid facelets', () {
    final c = CubieCube();
    expect(c.fromFacelet('X' * 54), isFalse);
    expect(c.fromFacelet(CubieCube.solvedFacelet.substring(0, 53)), isFalse);
    // Right length and alphabet but wrong colour counts (all U):
    expect(c.fromFacelet('U' * 54), isFalse);
  });

  test('moveIndex maps faces to the URFDLB-ordered move table', () {
    expect(CubieCube.moveIndex(Face.U, false), 0);
    expect(CubieCube.moveIndex(Face.U, true), 2);
    expect(CubieCube.moveIndex(Face.R, false), 3);
    expect(CubieCube.moveIndex(Face.F, false), 6);
    expect(CubieCube.moveIndex(Face.D, false), 9);
    expect(CubieCube.moveIndex(Face.L, false), 12);
    expect(CubieCube.moveIndex(Face.B, true), 17);
  });
}
