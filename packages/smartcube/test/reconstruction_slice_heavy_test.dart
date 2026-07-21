/// Regression for the blddb-fitted prior: fast slice-heavy execution. Three
/// takes of `U E L' E L2 E' L' U' E'` (UF-RF-DL) on a MoYu V10 — the capture
/// whose within-motion gaps overlap the between-motion mode (the first real
/// SMEARED verdict), so soft segmentation is doing real work here. Under the
/// old hand-corpus prior every take lost to a wide relabelling at a dead 0.00
/// margin and declined; the blddb prior recovers all three with real margins.
///
/// The margins also pin the commute-aware margin fix: the runner-ups within a
/// nat are same-axis reorderings of the truth (`E U` for `U E`), which are the
/// same physical claim and must not read as ambiguity.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';

import 'reconstruction_hardware_test.dart'
    show canonical, findOrientation, parseAlg;
import 'reconstruction_wide_moves_test.dart' show solveReconstruct;

final fixtureFile = File('test/fixtures/moyu_v10_slice_heavy_2026-07-21.jsonl');
const label = "U E L' E L2 E' L' U' E'";

List<List<CubeMove>> loadTakes() {
  final byKey = <String, List<CubeMove>>{};
  for (final line in fixtureFile.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final j = jsonDecode(line) as Map<String, dynamic>;
    byKey.putIfAbsent('${j['take']}', () => []).add(CubeMove(
          face: Face.values.byName(j['face'] as String),
          prime: j['prime'] as bool,
          cubeTimestamp: Duration(milliseconds: j['cubeMs'] as int),
        ));
  }
  return byKey.values.toList();
}

void main() {
  final skip =
      fixtureFile.existsSync() ? null : 'no capture at ${fixtureFile.path}';
  late List<List<CubeMove>> takes;

  setUpAll(() {
    if (fixtureFile.existsSync()) takes = loadTakes();
  });

  test('the capture loads three clean takes', () {
    expect(takes.length, 3);
    for (final t in takes) {
      expect(t.length, 14);
    }
  }, skip: skip);

  test('all takes reconstruct exactly on the solve path, none abstain', () {
    final truth = parseAlg(label);
    for (final moves in takes) {
      final rho0 = findOrientation(truth, moves);
      expect(rho0, isNotNull, reason: 'take does not match any orientation');
      final r = solveReconstruct(moves, rho0!);
      expect(r.abstained, isFalse,
          reason: 'declined at margin ${r.margin.toStringAsFixed(2)}');
      expect(canonical(r.moves), canonical(truth),
          reason: 'got ${r.notation}');
    }
  }, skip: skip);
}
