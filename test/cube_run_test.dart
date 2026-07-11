import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
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
    expect(c.onState(target), isNotNull);
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

  test('startCase returns false when the pair has no geometry', () {
    final c = make(AlgType.Custom);
    expect(c.startCase('AD', solved), isFalse);
    expect(c.expectedFacelets, isNull);
  });
}
