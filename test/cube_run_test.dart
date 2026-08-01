import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/smart_cube/cube_run.dart';
import 'package:three_style_trainer/smart_cube/three_style_geometry.dart';

const solved = CubieCube.solvedFacelet;

void main() {
  // A movable test clock.
  late DateTime clock;
  CubeRunController make(AlgType type) =>
      CubeRunController(type, now: () => clock);

  setUp(() => clock = DateTime(2026, 1, 1, 12, 0, 0));

  test('supports every 3-style type but not Custom', () {
    expect(CubeRunController.supports(AlgType.Corner), isTrue);
    expect(CubeRunController.supports(AlgType.Edge), isTrue);
    expect(CubeRunController.supports(AlgType.TwoFlip), isTrue);
    expect(CubeRunController.supports(AlgType.TwoTwist), isTrue);
    expect(CubeRunController.supports(AlgType.Parity), isTrue);
    expect(CubeRunController.supports(AlgType.Custom), isFalse);
  });

  test('starts idle, then recognition once a case begins', () {
    final c = make(AlgType.Corner);
    expect(c.phase, CubePhase.idle);
    c.startCase('AD', solved);
    expect(c.phase, CubePhase.recognition);
  });

  test('a run can begin from a scrambled (non-solved) state', () {
    final c = make(AlgType.Corner);
    final scrambled =
        ThreeStyleGeometry.expectedAfterPair(solved, 'AD', AlgType.Corner)!;
    expect(c.startCase('BW', scrambled), isTrue);
    final expected =
        ThreeStyleGeometry.expectedAfterPair(scrambled, 'BW', AlgType.Corner)!;
    expect(c.expectedFacelets, expected);
  });

  test('full case: recognition then execution split, auto-completes at E', () {
    final c = make(AlgType.Corner);
    expect(c.startCase('AD', solved), isTrue);
    expect(c.phase, CubePhase.recognition);

    final expected =
        ThreeStyleGeometry.expectedAfterPair(solved, 'AD', AlgType.Corner)!;
    expect(c.expectedFacelets, expected);

    // A state update before any move does nothing (still recognizing).
    expect(c.onState(solved), isNull);
    expect(c.phase, CubePhase.recognition);

    // First move ends recognition.
    clock = clock.add(const Duration(milliseconds: 1500));
    final recog = c.onMove();
    expect(recog, const Duration(milliseconds: 1500));
    expect(c.phase, CubePhase.execution);

    // Later moves during execution return nothing.
    clock = clock.add(const Duration(milliseconds: 200));
    expect(c.onMove(), isNull);

    // Intermediate (wrong) states don't complete.
    expect(c.onState(solved), isNull);
    expect(c.phase, CubePhase.execution);

    // Reaching the expected state completes and reports the split.
    clock = clock.add(const Duration(milliseconds: 800));
    final split = c.onState(expected);
    expect(split, isNotNull);
    expect(split!.recognition, const Duration(milliseconds: 1500));
    expect(split.execution, const Duration(milliseconds: 1000)); // 200 + 800
    expect(split.total, const Duration(milliseconds: 2500));
    expect(c.phase, CubePhase.complete);
  });

  test('a wrong (inverted) case never auto-completes', () {
    final c = make(AlgType.Corner);
    c.startCase('AD', solved);
    c.onMove();
    // Execute DA (the inverse) instead — settles at a different state.
    final wrong =
        ThreeStyleGeometry.expectedAfterPair(solved, 'DA', AlgType.Corner)!;
    expect(c.onState(wrong), isNull);
    expect(c.phase, CubePhase.execution);
  });

  test('rebaseline lets the shown pair complete from the botched state', () {
    final c = make(AlgType.Corner);
    c.startCase('AD', solved);
    c.onMove();
    // Executed a different case (AB) — AD does not complete.
    final afterWrong =
        ThreeStyleGeometry.expectedAfterPair(solved, 'AB', AlgType.Corner)!;
    expect(c.onState(afterWrong), isNull);

    // Re-baseline onto it; now AD from here reaches the (new) expected state.
    c.rebaseline('AD', afterWrong);
    final target =
        ThreeStyleGeometry.expectedAfterPair(afterWrong, 'AD', AlgType.Corner)!;
    expect(c.expectedFacelets, target);
    final split = c.onState(target);
    expect(split, isNotNull);
    // A re-baseline replaces the start state, so this counts as solved from it.
    expect(split!.recovered, isFalse);
    expect(c.phase, CubePhase.complete);
  });

  test('second case baselines on the prior end state', () {
    final c = make(AlgType.Corner);
    final e1 =
        ThreeStyleGeometry.expectedAfterPair(solved, 'AD', AlgType.Corner)!;
    c.startCase('AD', solved);
    c.onMove();
    c.onState(e1);

    // Next case starts from e1 (cube is no longer solved).
    c.startCase('BW', e1);
    final e2 = ThreeStyleGeometry.expectedAfterPair(e1, 'BW', AlgType.Corner)!;
    expect(c.expectedFacelets, e2);
    c.onMove();
    expect(c.onState(e2), isNotNull);
    expect(c.phase, CubePhase.complete);
  });

  test('parity completes on the solver\'s own edge swap', () {
    final c = make(AlgType.Parity);
    expect(c.startCase('A', solved), isTrue);
    c.onMove();
    // Corners as expected, but DF/DB swapped instead of the expected UF/UR.
    final exp =
        ThreeStyleGeometry.expectedAfterPair(solved, 'A', AlgType.Parity)!;
    final own = _swapEdges(_swapEdges(exp, 1, 0), 5, 7);
    expect(c.onState(own), isNotNull);
    expect(c.phase, CubePhase.complete);
    // The next case must baseline on where the cube really is, not on the
    // representative end state.
    expect(c.expectedFacelets, own);
  });

  test('parity does not complete on the corner swap alone', () {
    final c = make(AlgType.Parity);
    c.startCase('A', solved);
    c.onMove();
    final exp =
        ThreeStyleGeometry.expectedAfterPair(solved, 'A', AlgType.Parity)!;
    expect(c.onState(_swapEdges(exp, 1, 0)), isNull);
    expect(c.phase, CubePhase.execution);
  });

  test('startCase returns false when the pair has no geometry', () {
    final c = make(AlgType.Custom);
    expect(c.startCase('AD', solved), isFalse);
    expect(c.expectedFacelets, isNull);
  });

  test('addBaseline lets the shown pair complete from a botched state', () {
    final c = make(AlgType.Corner);
    c.startCase('AD', solved);
    c.onMove();
    // A botch settles on some other case's state; register it as a candidate.
    final botched =
        ThreeStyleGeometry.expectedAfterPair(solved, 'AB', AlgType.Corner)!;
    expect(c.onState(botched), isNull);
    expect(c.addBaseline('AD', botched), isTrue);
    // AD executed from the botched state now completes — no undo/reset needed —
    // but off a later baseline, so it counts as a recovery.
    final fromBotch =
        ThreeStyleGeometry.expectedAfterPair(botched, 'AD', AlgType.Corner)!;
    final split = c.onState(fromBotch);
    expect(split, isNotNull);
    expect(split!.recovered, isTrue);
    expect(c.phase, CubePhase.complete);
  });

  group('a case baselined on a state the cube has already left', () {
    // Where the cube really is: the case was baselined a turn before this.
    final real = (CubieCube()..applyMove(Face.U, false)).toFaceCube();
    final done =
        ThreeStyleGeometry.expectedAfterPair(real, 'AD', AlgType.Corner)!;

    test('a state seen before the first move re-anchors it', () {
      final c = make(AlgType.Corner);
      c.startCase('AD', solved);
      // Nothing turned yet, so what the cube reports is where it is.
      expect(c.onState(real), isNull);
      expect(c.phase, CubePhase.recognition);
      c.onMove();
      expect(c.onState(done), isNotNull);
    });

    test('without that, executing the alg completes nothing', () {
      final c = make(AlgType.Corner);
      c.startCase('AD', solved);
      c.onMove();
      expect(c.onState(done), isNull);
      // Only a rest, adopted as a baseline, makes the case completable again.
      c.addBaseline('AD', done);
      expect(
          c.onState(
              ThreeStyleGeometry.expectedAfterPair(done, 'AD', AlgType.Corner)!),
          isNotNull);
    });
  });

  test('re-baselining at the first move makes a clean solve honest', () {
    final c = make(AlgType.Corner);
    // Whatever we predicted, the cube reports this the moment it is turned.
    final real = (CubieCube()..applyMove(Face.U, false)).toFaceCube();
    c.startCase('AD', solved);
    c.rebaseline('AD', real);
    c.onMove();
    final split = c.onState(
        ThreeStyleGeometry.expectedAfterPair(real, 'AD', AlgType.Corner)!);
    expect(split, isNotNull);
    expect(split!.recovered, isFalse,
        reason: 'the cube simply sat there — nothing to recover from');
  });

  test('a stray move before the alg completes as a recovery', () {
    final c = make(AlgType.Corner);
    c.startCase('AD', solved);
    c.onMove();
    // One R, then a pause; AD from there completes, but the R stays on the cube.
    final afterR = (CubieCube()..applyMove(Face.R, false)).toFaceCube();
    c.addBaseline('AD', afterR);
    final done =
        ThreeStyleGeometry.expectedAfterPair(afterR, 'AD', AlgType.Corner)!;
    final split = c.onState(done);
    expect(split, isNotNull);
    expect(split!.recovered, isTrue);
  });

  test('moves that cancel out still complete from the start baseline', () {
    final c = make(AlgType.Corner);
    final e = ThreeStyleGeometry.expectedAfterPair(solved, 'AD', AlgType.Corner)!;
    c.startCase('AD', solved);
    c.onMove();
    // R R' mid-alg: the pause adds a baseline, but the alg still lands on
    // Δ_AD(start) — honest, not a recovery.
    final afterR = (CubieCube()..applyMove(Face.R, false)).toFaceCube();
    c.addBaseline('AD', afterR);
    final split = c.onState(e);
    expect(split, isNotNull);
    expect(split!.recovered, isFalse);
  });

  test('a mid-alg pause baseline never blocks completion from the start', () {
    final c = make(AlgType.Corner);
    final e = ThreeStyleGeometry.expectedAfterPair(solved, 'AD', AlgType.Corner)!;
    c.startCase('AD', solved);
    c.onMove();
    // User pauses mid-alg on a non-completing intermediate state.
    final mid =
        ThreeStyleGeometry.expectedAfterPair(solved, 'AB', AlgType.Corner)!;
    expect(c.onState(mid), isNull);
    c.addBaseline('AD', mid);
    // Finishing the alg reaches Δ_AD(start) — completes via baseline 0, honest.
    final split = c.onState(e);
    expect(split, isNotNull);
    expect(split!.recovered, isFalse);
    expect(c.phase, CubePhase.complete);
  });

  test('extra baselines never let a wrong alg auto-complete', () {
    final c = make(AlgType.Corner);
    c.startCase('AD', solved);
    c.onMove();
    final b1 =
        ThreeStyleGeometry.expectedAfterPair(solved, 'AB', AlgType.Corner)!;
    c.addBaseline('AD', b1);
    // DA (AD inverted) from either baseline matches no held expected state.
    final wrongFromSolved =
        ThreeStyleGeometry.expectedAfterPair(solved, 'DA', AlgType.Corner)!;
    final wrongFromB1 =
        ThreeStyleGeometry.expectedAfterPair(b1, 'DA', AlgType.Corner)!;
    expect(c.onState(wrongFromSolved), isNull);
    expect(c.onState(wrongFromB1), isNull);
    expect(c.phase, CubePhase.execution);
  });

  test('baselines are exposed oldest first, case start pinned at index 0', () {
    final c = make(AlgType.Corner);
    c.startCase('AD', solved);
    expect(c.baselines, [solved]);
    expect(c.caseStartFacelets, solved);
    c.onMove();
    final b1 =
        ThreeStyleGeometry.expectedAfterPair(solved, 'AB', AlgType.Corner)!;
    c.addBaseline('AD', b1);
    expect(c.baselines, [solved, b1]);
    expect(c.caseStartFacelets, solved,
        reason: 'a mid-case baseline must not move the case-start reference');
  });

  test('duplicate baselines are ignored', () {
    final c = make(AlgType.Corner);
    c.startCase('AD', solved);
    c.onMove();
    // Re-adding the case-start state is a no-op; the latest stays put.
    expect(c.addBaseline('AD', solved), isTrue);
    expect(c.baselines, [solved]);
  });

  group('a wrong alg is named whatever the user rested at', () {
    // Shown AD, user executes DA (a different case) instead.
    final pool = enumerateAlgs(AlgType.Corner);
    String wrongEnd(String from) =>
        ThreeStyleGeometry.expectedAfterPair(from, 'DA', AlgType.Corner)!;

    test('executed straight through from the case start', () {
      final c = make(AlgType.Corner);
      c.startCase('AD', solved);
      c.onMove();
      final end = wrongEnd(solved);
      expect(c.onState(end), isNull, reason: 'DA is not AD');
      expect(
          ThreeStyleGeometry.executedOtherPair(
              end, c.baselines, AlgType.Corner, pool,
              shown: 'AD'),
          'DA');
    });

    test('executed with a pause part-way through', () {
      final c = make(AlgType.Corner);
      c.startCase('AD', solved);
      c.onMove();
      // The >500ms hesitation that used to hide the mistake.
      final pause =
          ThreeStyleGeometry.expectedAfterPair(solved, 'AB', AlgType.Corner)!;
      c.addBaseline('AD', pause);
      final end = wrongEnd(solved);
      expect(c.onState(end), isNull);
      expect(
          ThreeStyleGeometry.executedOtherPair(
              end, c.baselines, AlgType.Corner, pool,
              shown: 'AD'),
          'DA',
          reason: 'a pause must not stop the wrong alg being named');
    });

    test('executed from a botched state the user rested at', () {
      final c = make(AlgType.Corner);
      c.startCase('AD', solved);
      c.onMove();
      final botch =
          ThreeStyleGeometry.expectedAfterPair(solved, 'AB', AlgType.Corner)!;
      c.addBaseline('AD', botch);
      final end = wrongEnd(botch); // DA executed from the botched state
      expect(
          ThreeStyleGeometry.executedOtherPair(
              end, c.baselines, AlgType.Corner, pool,
              shown: 'AD'),
          'DA');
    });

    test('the shown case executed correctly is never called wrong', () {
      final c = make(AlgType.Corner);
      c.startCase('AD', solved);
      c.onMove();
      final pause =
          ThreeStyleGeometry.expectedAfterPair(solved, 'AB', AlgType.Corner)!;
      c.addBaseline('AD', pause);
      final end =
          ThreeStyleGeometry.expectedAfterPair(solved, 'AD', AlgType.Corner)!;
      expect(
          ThreeStyleGeometry.executedOtherPair(
              end, c.baselines, AlgType.Corner, pool,
              shown: 'AD'),
          isNull);
      final split = c.onState(end);
      expect(split, isNotNull);
      expect(split!.recovered, isFalse,
          reason: 'pausing mid-alg is not a botch');
    });
  });
}

// Swap edge pieces [a] and [b] in [s].
String _swapEdges(String s, int a, int b) {
  final out = s.split('');
  final fa = CubieCube.eFacelet[a];
  final fb = CubieCube.eFacelet[b];
  for (var k = 0; k < 2; k++) {
    out[fa[k]] = s[fb[k]];
    out[fb[k]] = s[fa[k]];
  }
  return out.join();
}
