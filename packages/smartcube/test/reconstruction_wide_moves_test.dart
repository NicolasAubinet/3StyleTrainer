/// Regression for plan §31k: wide moves in solve replays. Nine takes on a
/// MoYu V10 — 4× `u L' E' L2 E L' u'` (UF-DL-RB) and 5× `E R E' R' U' R E R' u`
/// (UF-BR-UR). With wides out of the vocabulary the second family was
/// CONFIDENTLY wrong (`… R' D`, margin 1.79, claiming a net drift the cube
/// physically cannot end a completed case with). The solve path admits wides,
/// asserts the frame closes, and scores outer-after-slice transitions with the
/// blddb conditional (§31i.G) — under which BOTH families reconstruct exactly.
/// The bar is the §31j one — never confidently wrong — plus exact recovery.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';

import 'reconstruction_hardware_test.dart'
    show canonical, findOrientation, parseAlg;

final fixtureFile = File('test/fixtures/moyu_v10_wide_moves_2026-07-21.jsonl');

Map<String, List<List<CubeMove>>> loadByLabel() {
  final byKey = <String, List<CubeMove>>{};
  for (final line in fixtureFile.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final j = jsonDecode(line) as Map<String, dynamic>;
    byKey.putIfAbsent('${j['label']}#${j['take']}', () => []).add(CubeMove(
          face: Face.values.byName(j['face'] as String),
          prime: j['prime'] as bool,
          cubeTimestamp: Duration(milliseconds: j['cubeMs'] as int),
        ));
  }
  final byLabel = <String, List<List<CubeMove>>>{};
  byKey.forEach((k, v) {
    byLabel.putIfAbsent(k.split('#').first, () => []).add(v);
  });
  return byLabel;
}

/// The solve-path configuration: wides admitted, frame must close, and the
/// after-slice face prior on (mirrors MoveReconstruction.describe with
/// completed: true). Threshold is the default 0.5 — the 0.75 the wide space
/// once needed fenced off a wrong parse the after-slice term now defeats.
Reconstruction solveReconstruct(List<CubeMove> moves, FaceRotation rho0) =>
    reconstruct(
      moves,
      startOrientation: rho0,
      timing: TimingQuality.perMoveClock,
      weights: const ReconstructionWeights(
          allowWideMoves: true, useAfterSlicePrior: true),
      requireClosedDrift: true,
    );

void main() {
  final skip = fixtureFile.existsSync()
      ? null
      : 'no capture at ${fixtureFile.path}';
  late Map<String, List<List<CubeMove>>> byLabel;

  setUpAll(() {
    if (fixtureFile.existsSync()) byLabel = loadByLabel();
  });

  test('the capture loads both algs', () {
    expect(byLabel.keys, containsAll(["u L' E' L2 E L' u'", "E R E' R' U' R E R' u"]));
    expect(byLabel.values.fold<int>(0, (n, t) => n + t.length), 9);
  }, skip: skip);

  test('no take is ever confidently wrong under the solve configuration', () {
    final wrong = <String>[];
    byLabel.forEach((label, takes) {
      final truth = parseAlg(label);
      for (final moves in takes) {
        final rho0 = findOrientation(truth, moves);
        expect(rho0, isNotNull, reason: '$label was executed as labelled');
        final r = solveReconstruct(moves, rho0!);
        if (canonical(r.moves) != canonical(truth) && !r.abstained) {
          wrong.add('$label -> ${r.notation} '
              '(margin ${r.margin.toStringAsFixed(2)})');
        }
      }
    });
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  }, skip: skip);

  test('the trailing-wide alg reconstructs exactly on clean takes', () {
    final takes = byLabel["E R E' R' U' R E R' u"]!;
    final truth = parseAlg("E R E' R' U' R E R' u");
    var exact = 0;
    for (final moves in takes) {
      final r = solveReconstruct(moves, findOrientation(truth, moves)!);
      if (canonical(r.moves) == canonical(truth)) exact++;
    }
    // All 5 score margin 1.75 under the shipped weights; ≥4 leaves room for a
    // borderline take without letting the vocabulary silently regress.
    expect(exact, greaterThanOrEqualTo(4), reason: '$exact/5 exact');
  }, skip: skip);

  test('the bracketing-wides alg reconstructs exactly', () {
    // The hardest case of the three: two wides bracketing the whole alg, no
    // timing signature at all. The blddb population prior alone left the truth
    // +1.32 behind the all-outer relabelling; the after-slice face prior is
    // what flips it (the relabelling pairs its slices with F, real algs pair
    // them with L), to margin 0.55 on all four takes. If this regresses to an
    // abstention, the after-slice term or the 0.5 threshold moved.
    final takes = byLabel["u L' E' L2 E L' u'"]!;
    final truth = parseAlg("u L' E' L2 E L' u'");
    var exact = 0;
    for (final moves in takes) {
      final r = solveReconstruct(moves, findOrientation(truth, moves)!);
      if (canonical(r.moves) == canonical(truth) && !r.abstained) exact++;
    }
    expect(exact, greaterThanOrEqualTo(3), reason: '$exact/4 exact');
  }, skip: skip);

  test('without the closed-drift guarantee the old failure returns', () {
    // Pins that requireClosedDrift is load-bearing: the mistake path (which
    // cannot assert it) must not silently inherit the solve behaviour.
    final truth = parseAlg("E R E' R' U' R E R' u");
    final moves = byLabel["E R E' R' U' R E R' u"]!.first;
    final r = reconstruct(
      moves,
      startOrientation: findOrientation(truth, moves)!,
      timing: TimingQuality.perMoveClock,
    );
    expect(canonical(r.moves) == canonical(truth), isFalse);
  }, skip: skip);
}
