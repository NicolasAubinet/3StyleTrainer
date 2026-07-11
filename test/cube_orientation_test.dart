import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/smart_cube/cube_orientation.dart';
import 'package:three_style_trainer/smart_cube/three_style_geometry.dart';

const solved = CubieCube.solvedFacelet;

void main() {
  group('CubeOrientation', () {
    test('white/green is the identity', () {
      final s = CubeOrientation.normaliseFacelets(solved,
          top: CubeColour.white, front: CubeColour.green);
      expect(s, solved);
      // A scrambled state is untouched too.
      final scrambled = ThreeStyleGeometry.expectedAfterPair(
          solved, 'AD', AlgType.Corner)!;
      expect(
          CubeOrientation.normaliseFacelets(scrambled,
              top: CubeColour.white, front: CubeColour.green),
          scrambled);
    });

    test('a solved cube stays solved from any valid orientation', () {
      for (final top in CubeColour.values) {
        for (final front in CubeOrientation.frontsFor(top)) {
          expect(
              CubeOrientation.normaliseFacelets(solved, top: top, front: front),
              solved,
              reason: 'top=$top front=$front');
        }
      }
    });

    test('each valid orientation has exactly 4 fronts (adjacent faces)', () {
      for (final top in CubeColour.values) {
        expect(CubeOrientation.frontsFor(top).length, 4, reason: 'top=$top');
        expect(CubeOrientation.frontsFor(top), isNot(contains(top)));
      }
    });

    test('normalise and denormalise are inverses', () {
      final scrambled =
          ThreeStyleGeometry.expectedAfterPair(solved, 'AD', AlgType.Corner)!;
      for (final top in CubeColour.values) {
        for (final front in CubeOrientation.frontsFor(top)) {
          final user = CubeOrientation.denormaliseFacelets(scrambled,
              top: top, front: front);
          final back = CubeOrientation.normaliseFacelets(user,
              top: top, front: front);
          expect(back, scrambled, reason: 'top=$top front=$front');
          // Any orientation of a real state is still a structurally valid cube.
          expect(CubieCube().fromFacelet(user), isTrue);
        }
      }
    });

    test('white/red is a real reorientation (not identity)', () {
      expect(
          CubeOrientation.normaliseFacelets(
              ThreeStyleGeometry.expectedAfterPair(solved, 'AD', AlgType.Corner)!,
              top: CubeColour.white,
              front: CubeColour.red),
          isNot(ThreeStyleGeometry.expectedAfterPair(
              solved, 'AD', AlgType.Corner)));
    });
  });

  group('completion detection through orientation normalisation', () {
    // A case executed in the user's holding frame completes once its states are
    // normalised back to standard — the core reason §13 exists.
    test('corner case completes when held white-top/red-front', () {
      const top = CubeColour.white, front = CubeColour.red;
      // Standard-frame start + expected for the case.
      const start = solved;
      final expected =
          ThreeStyleGeometry.expectedAfterPair(start, 'AD', AlgType.Corner)!;
      // What the cube reports while the user holds it rotated.
      final startReported =
          CubeOrientation.denormaliseFacelets(start, top: top, front: front);
      final expectedReported =
          CubeOrientation.denormaliseFacelets(expected, top: top, front: front);
      // The trainer normalises every incoming state before geometry.
      final startNorm = CubeOrientation.normaliseFacelets(startReported,
          top: top, front: front);
      final currentNorm = CubeOrientation.normaliseFacelets(expectedReported,
          top: top, front: front);
      expect(
          ThreeStyleGeometry.isPairComplete(
              currentNorm, startNorm, 'AD', AlgType.Corner),
          isTrue);
      // And without normalisation it would NOT complete (proves the bug).
      expect(
          ThreeStyleGeometry.isPairComplete(
              expectedReported, startReported, 'AD', AlgType.Corner),
          isFalse);
    });
  });
}
