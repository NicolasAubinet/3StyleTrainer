import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
import 'package:smartcube/src/reconstruct/frame_algebra.dart';
import 'package:smartcube/src/reconstruct/reconstruction.dart';
import 'package:smartcube/src/reconstruct/solver_move.dart';

import 'reconstruction_hardware_test.dart' show canonical, parseAlg;

// 15ms apart: a real single motion. Wider spacing would split into separate
// motions and the direction tests below would pass without exercising anything.
List<CubeMove> turns(List<String> toks, {int spacing = 15}) {
  var t = 0;
  return [
    for (final tok in toks)
      CubeMove(
        face: Face.values.byName(tok.substring(0, 1)),
        prime: tok.endsWith("'"),
        cubeTimestamp: Duration(milliseconds: t += spacing),
      )
  ];
}

Reconstruction run(List<CubeMove> moves) => reconstruct(moves,
    startOrientation: kIdentity, timing: TimingQuality.perMoveClock);

void main() {
  group('a phantom half slice cannot be invented', () {
    // These four turns land in one motion and split 2/2 over opposite faces,
    // which used to be the whole test. But each face turns BOTH ways, so no
    // half turn happened. Reading it as a slice was wrong twice over: the
    // notation, and the drift it injects into every following move.
    test('mixed directions are not a half slice', () {
      // A quarter slice built from a valid sub-pair is still fair game here —
      // R R' L L legitimately reads as R M' L. What must not appear is a HALF
      // slice, which needs both turns on each face to go the same way.
      for (final c in [
        ['F', 'B', 'B', "F'"],
        ['R', "R'", 'L', 'L'],
        ['R', 'R', 'L', "L'"],
        ['R', "R'", 'L', "L'"],
      ]) {
        final halves = run(turns(c))
            .moves
            .where((m) => m.kind == MoveKind.slice && m.amount == 2);
        expect(halves, isEmpty, reason: c.join(' '));
      }
    });

    test('a real half slice is still recognised', () {
      expect(run(turns(['R', 'R', "L'", "L'"])).notation, 'M2');
      expect(run(turns(['U', 'U', "D'", "D'"])).notation, 'E2');
    });

    test('the phantom slice no longer misframes what follows', () {
      // F B B F' then a plain U. Under the old reading the F B B F' became S2,
      // whose z drift relabelled the U into something else entirely. A quarter
      // S from the valid (B, F') sub-pair is fair game — but then the trailing
      // turn must be framed by THAT drift (z reads it as R), not by a phantom.
      final moves = turns(['F', 'B', 'B', "F'"])
        ..add(CubeMove(
            face: Face.U,
            prime: false,
            cubeTimestamp: const Duration(milliseconds: 400)));
      final r = run(moves);
      expect(
          r.moves.where((m) => m.kind == MoveKind.slice && m.amount == 2),
          isEmpty);
      // The S may be spelt inside a wide (`F S` nets to `Fw`); either way it
      // carries the z drift that must reframe the trailing turn.
      final zDrift = ['S', 'Fw', 'Bw'].any(r.notation.contains);
      expect(r.notation, zDrift ? endsWith('R') : endsWith('U'));
    });
  });

  group('motions too long to parse', () {
    test('are declined rather than reported with infinite confidence', () {
      // Six turns 10ms apart: one "motion" no hand could make. The old code
      // returned a single reading, so nothing differed from it and the margin
      // came back as infinity — maximum confidence for an unparseable group.
      final r = run(turns(['R', "L'", 'B', "F'", "L'", 'R'], spacing: 10));
      expect(r.abstained, isTrue);
      expect(r.margin, isNot(double.infinity));
      expect(r.note, isNotNull);
      expect(r.moves.every((m) => m.kind == MoveKind.outer), isTrue);
    });

    test('a fast run of ordinary turns does not chain into one motion', () {
      // Each gap is inside the 60ms window, but the run as a whole is far
      // longer than any single motion. Real captures do contain 50ms gaps.
      final six = turns(['R', 'U', 'F', 'L', 'D', 'B'], spacing: 50);
      expect(segmentMotions(six).length, greaterThan(1));
      expect(run(six).abstained, isFalse);
    });

    test('a genuine four-turn half slice still fits in one motion', () {
      expect(segmentMotions(turns(['R', 'R', "L'", "L'"], spacing: 15)).length, 1);
    });
  });

  group('timing quality', () {
    test('no clock declines and returns the raw reading', () {
      final moves = turns(["R'", 'L'], spacing: 10);
      final r = reconstruct(moves,
          startOrientation: kIdentity, timing: TimingQuality.none);
      expect(r.abstained, isTrue);
      expect(r.degraded, isTrue);
      expect(r.notation, "R' L");
    });

    test('a coarse clock answers but flags itself', () {
      final moves = turns(["R'", 'L'], spacing: 10);
      final r = reconstruct(moves,
          startOrientation: kIdentity, timing: TimingQuality.coarse);
      expect(r.degraded, isTrue);
    });
  });

  test('an empty stream is not an error', () {
    expect(run(const []).moves, isEmpty);
  });

  group('same-axis runs are netted', () {
    String simplify(String alg) =>
        movesToString(simplifyAxisRuns(parseAlg(alg)));

    test('a wide executed around a slice is just the bigger slice', () {
      // Captured from real execution of an M2: honest reading, one move.
      expect(simplify("Rw M' R'"), 'M2');
      expect(simplify("M' U R' U' Rw M' R' U R U' M'"),
          "M' U R' U' M2 U R U' M'");
    });

    test('an outer-plus-slice pair turning together is a wide', () {
      expect(simplify("R M'"), 'Rw');
      expect(simplify("R' M"), "Rw'");
      expect(simplify('F S'), 'Fw');
    });

    test('already minimal runs keep their captured order', () {
      expect(simplify('R M'), 'R M');
      expect(simplify("U D'"), "U D'");
      expect(simplify('E U'), 'E U');
    });

    test('full cancellations collapse across an emptied run', () {
      expect(simplifyAxisRuns(parseAlg("R U U' R'")), isEmpty);
    });

    test('canonical mode gives commuted spellings one name', () {
      String key(String alg) =>
          movesToString(simplifyAxisRuns(parseAlg(alg), canonical: true));
      expect(key('E U'), key('U E'));
      expect(key("Rw M' R'"), key('M2'));
    });

    test('end to end: an M2 fingered as Rw M\' R\' displays as M2', () {
      // The scÈ report: the hands did Rw M' R' — a perfect capture — but the
      // case is M' U R' U' M2 U R U' M', and that is what the replay must say.
      final r = solveRun(execute("M' U R' U' Rw M' R' U R U' M'"));
      expect(r.abstained, isFalse);
      expect(r.notation, "M' U R' U' M2 U R U' M'");
    });
  });

  group('corrected mistakes', () {
    test('a do-undo prefix is shown in parentheses, not parsed into the alg',
        () {
      // The fu/hé report: starting a case with L' L (or D' D) either dragged
      // those quarters into slice hypotheses — near-tie, raw-reading fallback —
      // or vanished silently. They must parse as an inert correction instead.
      final moves = [
        CubeMove(
            face: Face.L,
            prime: true,
            cubeTimestamp: const Duration(milliseconds: 100)),
        CubeMove(
            face: Face.L,
            prime: false,
            cubeTimestamp: const Duration(milliseconds: 400)),
        ...execute("M' U R' U' M2 U R U' M'", t0: 1000),
      ];
      final r = solveRun(moves);
      expect(r.abstained, isFalse);
      expect(r.notation, "(L' L) M' U R' U' M2 U R U' M'");
    });

    test('a mid-solve correction is spelled in the drifted frame', () {
      // A U done and undone AFTER an M' arrives as F F' in the cube's rotated
      // frame; the replay must still call it (U U'). Stream built by hand:
      // M' [mistake U, undo U'] U M U'.
      CubeMove mv(String face, bool prime, int t) => CubeMove(
          face: Face.values.byName(face),
          prime: prime,
          cubeTimestamp: Duration(milliseconds: t));
      final r = solveRun([
        mv('R', true, 200), mv('L', false, 215), // M'
        mv('F', false, 500), // mistake U, reported through x drift
        mv('F', true, 800), // its undo
        mv('F', false, 1100), // the real U
        mv('R', false, 1400), mv('L', true, 1415), // M
        mv('U', true, 1700), // the real U'
      ]);
      expect(r.abstained, isFalse);
      // Two equal-cost strippings exist — (U U') U and U (U' U) — and they are
      // the same physical claim, so either spelling is a correct answer.
      expect(
          r.notation,
          anyOf("M' (U U') U M U'", "M' U (U' U) M U'"));
    });

    test('a do-undo prefix before a wide-opening alg is not smeared into it',
        () {
      // The yÈ report: D' D (or D D') before u L' E' L2 E L' u'. The u senses
      // as a single D, abutting the pre-move pair, and the beam used to
      // spread the do-undo around it (`D' Uw D` — a vacuous same-axis bracket
      // that collected the conjugate bonus) and win with a relabelled tail:
      // the user saw `Uw' D2 R' E' R2 D' U F' D'`. The correction reading
      // must win, keep the pair visible, and net to the plain alg.
      CubeMove mv(String face, bool prime, int t) => CubeMove(
          face: Face.values.byName(face),
          prime: prime,
          cubeTimestamp: Duration(milliseconds: t));
      // Both prefix orders against both wide openings (u senses D, u' senses
      // D'). When the prefix's undo shares the opening quarter's face the two
      // pairings tie exactly — the chU report saw `Uw' (D D') ...` — and the
      // earliest-correction tie-break must keep the pre-move pair FIRST.
      for (final alg in ["u L' E' L2 E L' u'", "u' R E R2 E' R u"]) {
        for (final prime in [true, false]) {
          final prefix = prime ? "(D' D)" : "(D D')";
          final r = solveRun([
            mv('D', prime, 100),
            mv('D', !prime, 400),
            ...execute(alg, t0: 900),
          ]);
          expect(r.abstained, isFalse,
              reason: '$prefix $alg declined at margin '
                  '${r.margin.toStringAsFixed(2)}');
          expect(canonical(r.moves), canonical(parseAlg(alg)),
              reason: r.notation);
          expect(r.notation, startsWith(prefix),
              reason: '$prefix $alg -> ${r.notation}');
        }
      }
    });

    test('a nested do-undo group is parenthesised whole', () {
      // The owner report: U R F F' R' U' before an alg showed only (F F').
      // The pairs nest — F F' cancels, which makes R...R' a cancelling pair,
      // then U...U' — so the entire fumble is one correction group.
      CubeMove mv(String face, bool prime, int t) => CubeMove(
          face: Face.values.byName(face),
          prime: prime,
          cubeTimestamp: Duration(milliseconds: t));
      final r = solveRun([
        mv('U', false, 100),
        mv('R', false, 400),
        mv('F', false, 700),
        mv('F', true, 1000),
        mv('R', true, 1300),
        mv('U', true, 1600),
        ...execute("M' U R' U' M2 U R U' M'", t0: 2200),
      ]);
      expect(r.abstained, isFalse,
          reason: 'declined at margin ${r.margin.toStringAsFixed(2)}');
      expect(r.notation, "(U R F F' R' U') M' U R' U' M2 U R U' M'");
    });

    test('corrections stay visible through the display simplifier', () {
      const cor = [
        SolverMove.outer(Face.L, 3, correction: true),
        SolverMove.outer(Face.L, 1, correction: true),
      ];
      final moves = [...cor, const SolverMove.outer(Face.L, 3)];
      expect(movesToString(simplifyAxisRuns(moves)), "(L' L) L'");
      // Canonical mode nets through them — every competing parse carries the
      // same corrections, so margin keys must not depend on their spelling.
      expect(movesToString(simplifyAxisRuns(moves, canonical: true)), "L'");
    });
  });
}

/// The solve-path configuration (mirrors MoveReconstruction.describe with
/// completed: true).
Reconstruction solveRun(List<CubeMove> moves) => reconstruct(
      moves,
      startOrientation: kIdentity,
      timing: TimingQuality.perMoveClock,
      weights: const ReconstructionWeights(
          allowWideMoves: true, useAfterSlicePrior: true),
      requireClosedDrift: true,
    );

/// The quarter-turn stream a cube reports for [alg] executed cleanly from
/// identity: one motion per move, quarters 15ms apart, motions 200ms apart.
List<CubeMove> execute(String alg, {int t0 = 0}) {
  var rho = kIdentity;
  var t = t0;
  final out = <CubeMove>[];
  for (final m in parseAlg(alg)) {
    final dec = switch (m.kind) {
      MoveKind.outer =>
        Decomposition([SensedTurn(m.face!, m.amount)], kIdentity),
      MoveKind.slice => decomposeSlice(m.slice!, m.amount),
      MoveKind.wide => decomposeWide(m.face!, m.amount),
    };
    t += 200;
    for (final s in dec.sensed) {
      for (var q = 0; q < (s.amount == 2 ? 2 : 1); q++) {
        out.add(CubeMove(
          face: toReportedFrame(s.face, rho),
          prime: s.amount == 3,
          cubeTimestamp: Duration(milliseconds: t),
        ));
        t += 15;
      }
    }
    rho = compose(dec.drift, rho);
  }
  return out;
}
