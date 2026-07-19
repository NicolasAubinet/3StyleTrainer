import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart' as sc;
import 'package:three_style_trainer/smart_cube/cube_orientation.dart';
import 'package:three_style_trainer/smart_cube/move_reconstruction.dart';

/// A stream of turns spaced like real solving: turns within one physical motion
/// land together, separate motions are ~150ms apart.
List<sc.CubeMove> stream(List<List<String>> motions) {
  final out = <sc.CubeMove>[];
  var t = 0;
  for (final motion in motions) {
    t += 150;
    for (var i = 0; i < motion.length; i++) {
      final tok = motion[i];
      final prime = tok.endsWith("'");
      out.add(sc.CubeMove(
        face: sc.Face.values.byName(prime ? tok.substring(0, 1) : tok),
        prime: prime,
        cubeTimestamp: Duration(milliseconds: t + i * 6),
      ));
    }
  }
  return out;
}

class _FakeCube implements sc.SmartCube {
  final sc.TimingQuality quality;
  _FakeCube(this.quality);
  @override
  sc.TimingQuality get timingQuality => quality;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('orientation bridge', () {
    test('white top / green front is the identity frame', () {
      expect(
        MoveReconstruction.orientationFor(
            top: CubeColour.white, front: CubeColour.green),
        sc.kIdentity,
      );
    });

    test('a rotated holding orientation is a real permutation of the 24', () {
      final rot = MoveReconstruction.orientationFor(
          top: CubeColour.white, front: CubeColour.red);
      expect(rot, isNot(sc.kIdentity));
      expect(rot.toSet().length, 6, reason: 'must be a permutation');
      expect(
        sc.rotationGroup().map(sc.orientationKey),
        contains(sc.orientationKey(rot)),
      );
    });

    test('agrees with the facelet normalisation the rest of the app uses', () {
      // Both paths must describe the same rotation, or moves and states would
      // disagree about which way the cube is being held.
      for (final (top, front) in [
        (CubeColour.white, CubeColour.green),
        (CubeColour.white, CubeColour.red),
        (CubeColour.yellow, CubeColour.blue),
        (CubeColour.green, CubeColour.white),
      ]) {
        final rot = MoveReconstruction.orientationFor(top: top, front: front);
        for (final f in sc.Face.values) {
          expect(
            sc.toSolverFrame(f, rot).name,
            CubeOrientation.normaliseFace(f.name, top: top, front: front),
            reason: 'face ${f.name} at top=$top front=$front',
          );
        }
      }
    });
  });

  group('describe', () {
    final cube = _FakeCube(sc.TimingQuality.perMoveClock);

    test('returns null when nothing was turned', () {
      expect(MoveReconstruction.describe(const [], cube: cube), isNull);
    });

    test('recovers a slice instead of two opposite face turns', () {
      // M' U R U' M U R' U'. The M' senses as R' + L in one motion and drifts
      // the frame by x, so the U that follows is reported as F (R and L are
      // fixed under x, which is why the R still reads as R). The M puts the
      // frame back, so the last three turns report unrotated.
      final moves = stream([
        ["R'", 'L'],
        ['F'],
        ['R'],
        ["F'"],
        ['R', "L'"],
        ['U'],
        ["R'"],
        ["U'"],
      ]);
      expect(MoveReconstruction.describe(moves, cube: cube),
          "M' U R U' M U R' U'");
    });

    test('two turns done at once are not mistaken for a slice', () {
      // R U D' R' — the U and D' are one two-handed motion, timing-identical to
      // an E slice. The conjugate R ... R' is what rules the slice out.
      final moves = stream([
        ['R'],
        ['U', "D'"],
        ["R'"],
      ]);
      expect(MoveReconstruction.describe(moves, cube: cube), "R U D' R'");
    });

    test('a cube with no clock falls back to plain face turns', () {
      final moves = stream([
        ["R'", 'L'],
        ['F'],
      ]);
      final out = MoveReconstruction.describe(moves,
          cube: _FakeCube(sc.TimingQuality.none))!;
      expect(out, isNot(contains('M')));
      expect(out, "R' L F");
    });

    test('no connected cube is treated as no clock, not as a good one', () {
      final moves = stream([
        ["R'", 'L'],
        ['F'],
      ]);
      expect(MoveReconstruction.describe(moves, cube: null), "R' L F");
    });
  });
}
