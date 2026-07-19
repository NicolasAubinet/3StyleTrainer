import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';

/// Pins the §31a drift table. The *sensed pair* column is hardware-validated
/// (§25); the *drift* column was confirmed by the §31g sign triage. These
/// tests exist so a refactor cannot silently flip a sign — a flipped sign
/// produces plausible-looking output that is systematically wrong.
void main() {
  String sensed(Decomposition d) => d.sensed.map((s) => s.toString()).join(' + ');

  group('slice sensed pairs (§31a, hardware-validated)', () {
    test('quarter turns', () {
      expect(sensed(decomposeSlice(Slice.M, 1)), 'R + L\'');
      expect(sensed(decomposeSlice(Slice.M, 3)), 'R\' + L');
      expect(sensed(decomposeSlice(Slice.E, 1)), 'U + D\'');
      expect(sensed(decomposeSlice(Slice.E, 3)), 'U\' + D');
      expect(sensed(decomposeSlice(Slice.S, 1)), 'F\' + B');
      expect(sensed(decomposeSlice(Slice.S, 3)), 'F + B\'');
    });

    test('half turns sense as 2+2 on opposite faces', () {
      expect(sensed(decomposeSlice(Slice.M, 2)), 'R2 + L2');
      expect(sensed(decomposeSlice(Slice.E, 2)), 'U2 + D2');
      expect(sensed(decomposeSlice(Slice.S, 2)), 'F2 + B2');
    });
  });

  group('drift (§31a, hardware-confirmed 2026-07-19, MoYu V10)', () {
    test('E drifts by y-prime: a following physical R reports as F', () {
      final rho = decomposeSlice(Slice.E, 1).drift;
      expect(rho, invert(kRotY));
      expect(toReportedFrame(Face.R, rho), Face.F);
      expect(toSolverFrame(Face.F, rho), Face.R);
      // The owner's worked example: U D' B U decodes to E L U, not E R U.
      expect(toSolverFrame(Face.B, rho), Face.L);
    });

    test('M-prime drifts by x: R and L are fixed', () {
      final rho = decomposeSlice(Slice.M, 3).drift;
      expect(rho, kRotX);
      expect(toReportedFrame(Face.R, rho), Face.R);
      expect(toReportedFrame(Face.L, rho), Face.L);
      expect(toReportedFrame(Face.U, rho), Face.F);
    });

    test('S drifts by z: F and B are fixed, a following U reports as L', () {
      final rho = decomposeSlice(Slice.S, 1).drift;
      expect(rho, kRotZ);
      expect(toReportedFrame(Face.F, rho), Face.F);
      expect(toReportedFrame(Face.U, rho), Face.L);
    });

    test('a slice and its inverse cancel', () {
      for (final s in Slice.values) {
        final net = compose(
            decomposeSlice(s, 3).drift, decomposeSlice(s, 1).drift);
        expect(isIdentity(net), isTrue, reason: '$s then ${s.name}\'');
      }
    });

    test('a half-turn slice is its own inverse', () {
      for (final s in Slice.values) {
        final d = decomposeSlice(s, 2).drift;
        expect(isIdentity(compose(d, d)), isTrue);
        // ...and is NOT the identity on its own: one M2 leaves the core rotated,
        // which is why the net-drift constraint must be soft (§31f).
        expect(isIdentity(d), isFalse);
      }
    });
  });

  group('wide moves', () {
    test('sense as a single turn on the OPPOSITE face, same amount', () {
      expect(sensed(decomposeWide(Face.R, 1)), 'L');
      expect(sensed(decomposeWide(Face.R, 3)), 'L\'');
      expect(sensed(decomposeWide(Face.R, 2)), 'L2');
      expect(sensed(decomposeWide(Face.U, 1)), 'D');
      expect(sensed(decomposeWide(Face.F, 1)), 'B');
    });

    test('Rw carries the drift of M-prime', () {
      expect(decomposeWide(Face.R, 1).drift, decomposeSlice(Slice.M, 3).drift);
    });
  });

  test('whole-cube rotations sense as nothing at all', () {
    for (var axis = 0; axis < 3; axis++) {
      expect(decomposeRotation(axis, 1).sensed, isEmpty);
      expect(isIdentity(decomposeRotation(axis, 1).drift), isFalse);
    }
  });

  test('the rotation group has 24 elements', () {
    expect(rotationGroup().length, 24);
  });

  group('halfSliceForTurns', () {
    // Regression: the parser used to check only "two faces, 2+2" and would read
    // F B B F' as S2 -- wrong notation, and a phantom drift that relabels every
    // move after it. The synthetic corpus could never produce a mixed-direction
    // pair, so only real-shaped input exposed it.
    ({Face face, bool prime}) t(String s) =>
        (face: Face.values.byName(s[0]), prime: s.endsWith("'"));

    test('recognises a genuine half slice, either way round', () {
      expect(halfSliceForTurns([t('R'), t('R'), t("L'"), t("L'")]), Slice.M);
      expect(halfSliceForTurns([t("R'"), t("R'"), t('L'), t('L')]), Slice.M);
      expect(halfSliceForTurns([t('U'), t('U'), t("D'"), t("D'")]), Slice.E);
      expect(halfSliceForTurns([t("F'"), t("F'"), t('B'), t('B')]), Slice.S);
    });

    test('rejects a pair that does not turn the same way', () {
      expect(halfSliceForTurns([t('F'), t('B'), t('B'), t("F'")]), isNull);
      expect(halfSliceForTurns([t('R'), t("R'"), t('L'), t('L')]), isNull);
      expect(halfSliceForTurns([t('R'), t('R'), t('L'), t("L'")]), isNull);
      expect(halfSliceForTurns([t('R'), t("R'"), t('L'), t("L'")]), isNull);
    });

    test('rejects adjacent faces and wrong counts', () {
      expect(halfSliceForTurns([t('R'), t('R'), t('U'), t('U')]), isNull);
      expect(halfSliceForTurns([t('R'), t('R'), t("L'")]), isNull);
      expect(halfSliceForTurns([t('R'), t('R'), t('R'), t('R')]), isNull);
    });
  });

  group('sliceForPair', () {
    test('recognises every quarter-turn slice, in either order', () {
      for (final s in Slice.values) {
        for (final amt in [1, 3]) {
          final d = decomposeSlice(s, amt);
          final a = d.sensed[0], b = d.sensed[1];
          expect(sliceForPair(a.face, a.amount, b.face, b.amount),
              (slice: s, amount: amt));
          expect(sliceForPair(b.face, b.amount, a.face, a.amount),
              (slice: s, amount: amt));
        }
      }
    });

    test('rejects an opposite pair turned the same way (not a slice)', () {
      // U + D is two outer turns in opposite global directions — U + D' is the
      // slice. This is what halves the candidate set for free.
      expect(sliceForPair(Face.U, 1, Face.D, 1), isNull);
      expect(sliceForPair(Face.R, 1, Face.L, 1), isNull);
    });

    test('rejects adjacent faces', () {
      expect(sliceForPair(Face.U, 1, Face.R, 3), isNull);
    });
  });
}
