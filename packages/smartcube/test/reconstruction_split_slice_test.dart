/// Regression for the confidently-wrong replay of plan §31j: `M U R' U' M2 U
/// R U' M` on a MoYu V10, five takes, the stiff middle layer landing each `M`
/// of the `M2` as two turns 122-285ms apart. Under hard segmentation the
/// correct parse was unreachable — not outranked, absent — and the parser
/// reported its best leftover with high confidence. The bar asserted here is
/// "never confidently wrong": declining is acceptable, being wrong is not.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';
import 'package:smartcube/src/reconstruct/reconstruction.dart'
    show kMotionGapMs, segmentMotions;

import 'reconstruction_hardware_test.dart'
    show canonical, findOrientation, parseAlg;

const label = "M U R' U' M2 U R U' M";

/// See the note on the other capture: personal recording, skip if absent.
final fixtureFile = File('test/fixtures/moyu_v10_split_slice_2026-07-20.jsonl');

List<List<CubeMove>> loadTakes() {
  final byTake = <int, List<CubeMove>>{};
  for (final line in fixtureFile.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final j = jsonDecode(line) as Map<String, dynamic>;
    byTake.putIfAbsent(j['take'] as int, () => []).add(CubeMove(
          face: Face.values.byName(j['face'] as String),
          prime: j['prime'] as bool,
          cubeTimestamp: Duration(milliseconds: j['cubeMs'] as int),
        ));
  }
  return byTake.values.toList();
}

void main() {
  final skip = fixtureFile.existsSync()
      ? null
      : 'no capture at ${fixtureFile.path}';
  late List<List<CubeMove>> takes;

  setUpAll(() {
    if (fixtureFile.existsSync()) takes = loadTakes();
  });

  test('the capture is lossless — 5 takes of 14 quarter turns', () {
    expect(takes.length, 5);
    for (final t in takes) {
      expect(t.length, 14, reason: 'the alg sends exactly 14 quarter turns');
    }
  }, skip: skip);

  test('the slice halves really do straddle the motion gap', () {
    // Pins the premise: a cleanly-executed replacement fixture should fail
    // here, not silently pass the test below for the wrong reason.
    var straddling = 0;
    for (final t in takes) {
      final motions = segmentMotions(t);
      // 14 turns intended as 9 moves; cleanly executed they group into fewer
      // motions than this.
      if (motions.length >= 10) straddling++;
    }
    expect(straddling, 5,
        reason: 'every take should show a slice split across motions');
  }, skip: skip);

  test('every take reconstructs, or declines — never confidently wrong', () {
    final truth = parseAlg(label);
    var exact = 0, declined = 0;
    final wrong = <String>[];

    for (final moves in takes) {
      final rho0 = findOrientation(truth, moves);
      expect(rho0, isNotNull, reason: 'the alg was executed as labelled');
      final r = reconstruct(moves,
          startOrientation: rho0!, timing: TimingQuality.perMoveClock);

      if (canonical(r.moves) == canonical(truth)) {
        exact++;
      } else if (r.abstained) {
        declined++;
      } else {
        wrong.add('${r.notation}  (margin ${r.margin.toStringAsFixed(2)})');
      }
    }

    expect(wrong, isEmpty,
        reason: 'confidently wrong on ${wrong.length}/5 takes:\n'
            '${wrong.join('\n')}');
    expect(exact, greaterThanOrEqualTo(4),
        reason: '$exact exact, $declined declined');
  }, skip: skip);

  test('a fusion cost high enough to forbid fusion returns the old failure', () {
    // If this ever passes trivially, soft segmentation has stopped doing
    // anything — fusion priced out of reach must reproduce the old failure.
    final truth = parseAlg(label);
    final moves = takes.first;
    final rho0 = findOrientation(truth, moves)!;
    final r = reconstruct(moves,
        startOrientation: rho0,
        timing: TimingQuality.perMoveClock,
        weights: const ReconstructionWeights(motionFusionCost: 1000));
    expect(canonical(r.moves), isNot(canonical(truth)));
  }, skip: skip);

  test('the motion gap constant is the one the premise assumes', () {
    expect(kMotionGapMs, 60);
  }, skip: skip);
}
