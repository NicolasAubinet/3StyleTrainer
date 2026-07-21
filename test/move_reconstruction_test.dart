import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart' as sc;
// Checks the app's orientation mapping against the frame algebra's own
// definitions, which are deliberately not part of the package's public surface.
// ignore: implementation_imports
import 'package:smartcube/src/reconstruct/frame_algebra.dart' as sc;
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
      expect(MoveReconstruction.describe(moves, cube: cube)?.notation,
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
      final out = MoveReconstruction.describe(moves, cube: cube)!;
      expect(out.notation, "R U D' R'");
      expect(out.reconstructed, isTrue);
    });

    test('a wrong-case execution gets the solve-path treatment', () {
      // The owner's A-parity sighting: `f U R U R2 U' D' R U R' D R2 U2 f'`
      // executed against a different shown case. Wrong-case detection fires on
      // the other pair's full expected state, so the centres are provably home
      // — completed: true is physically justified and the wide f recovers.
      final moves = stream([
        ['B'], ['L'], ['U'], ['L'], ['U', 'U'], ["L'"], ["R'"], ['U'], ['L'],
        ["U'"], ['R'], ["U'", "U'"], ["L'", "L'"], ["B'"],
      ]);
      final solve =
          MoveReconstruction.describe(moves, cube: cube, completed: true)!;
      expect(solve.notation, "Fw U R U R2 U' D' R U R' D R2 U2 Fw'");
      expect(solve.reconstructed, isTrue);
      // A requeue/skip has no completion guarantee: wides stay off and the
      // stream reads as the outer turns the cube sensed.
      final aborted = MoveReconstruction.describe(moves, cube: cube)!;
      expect(aborted.notation, "B L U L U2 L' R' U L U' R U2 L2 B'");
    });

    test('a slice pairing cannot skip over a cross-axis turn', () {
      // The owner's Q-parity bug: `S U' R U R2 F R f' U R U R' U'` replayed as
      // `S U' R U R2 S' U2 R U R' U'` — an S' whose "halves" were the separate
      // F and f' with a U in between, which is a physically DIFFERENT
      // transformation (executing it scrambles). A fused window must not pair
      // quarters across a non-commuting turn.
      final moves = stream([
        ["F'", 'B'], ["L'"], ['U'], ['L'], ['U', 'U'], ['F'], ['U'], ["B'"],
        ['U'], ['R'], ['U'], ["R'"], ["U'"],
      ]);
      final r =
          MoveReconstruction.describe(moves, cube: cube, completed: true)!;
      expect(r.notation, "S U' R U R2 F R Fw' U R U R' U'");
      expect(r.reconstructed, isTrue);
    });

    test('a cube with no clock falls back to plain face turns, and says so', () {
      final moves = stream([
        ["R'", 'L'],
        ['F'],
      ]);
      final out = MoveReconstruction.describe(moves,
          cube: _FakeCube(sc.TimingQuality.none))!;
      expect(out.notation, "R' L F");
      expect(out.reconstructed, isFalse,
          reason: 'a raw reading must not be presented as a reconstruction');
      expect(out.why, isNotNull);
    });

    test('a coarse clock is not passed off as a confident reading', () {
      final moves = stream([
        ["R'", 'L'],
        ['F'],
      ]);
      final out = MoveReconstruction.describe(moves,
          cube: _FakeCube(sc.TimingQuality.coarse))!;
      expect(out.reconstructed, isFalse);
    });

    test('no connected cube is treated as no clock, not as a good one', () {
      final moves = stream([
        ["R'", 'L'],
        ['F'],
      ]);
      final out = MoveReconstruction.describe(moves, cube: null)!;
      expect(out.notation, "R' L F");
      expect(out.reconstructed, isFalse);
    });
  });
}
