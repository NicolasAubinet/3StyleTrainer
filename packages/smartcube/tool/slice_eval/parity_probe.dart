/// Probe for the owner's reported A-parity miss: the app showed
/// `B L U L U2 L' R' U L U' R U2 L2 B'` for an execution that started with a
/// wide f. Synthesize candidate true algs, check which one senses as the
/// reported stream, and score it under the solve-path configuration.

import 'dart:math';

import 'algebra.dart';
import 'blddb.dart';
import 'methodb.dart';
import 'synth.dart';

const reportedRaw = "B L U L U2 L' R' U L U' R U2 L2 B'";

void main() {
  final st = fitBlddb().stats;
  final candidates = [
    // z-relabelled middle, both direction conventions:
    "f U R U R2 U' D' R U R' D R2 U2 f'",
    "f D L D L2 D' U' L D L' U L2 D2 f'",
    // and the raw reading itself as a control:
    reportedRaw,
    // The owner's Q-parity report (2026-07-21): reconstructed as
    // "S U' R U R2 S' U2 R U R' U'" — a DIFFERENT physical transformation.
    "S U' R U R2 F R f' U R U R' U'",
    // The wrong parse itself: if its sensed stream differs from the truth's,
    // the beam emitted a reading inconsistent with the observations.
    "S U' R U R2 S' U2 R U R' U'",
  ];

  final rawFaces = [
    for (final m in parseAlg(reportedRaw))
      for (var k = 0; k < (m.amount == 2 ? 2 : 1); k++) faceNames[m.id]
  ].join(' ');

  for (final alg in candidates) {
    final truth = parseAlg(alg);
    final res = synthesize(truth, Random(1));
    final sensed = res.stream.map((r) => faceNames[r.face]).join(' ');
    final match = sensed == rawFaces;
    print('${match ? "MATCH " : "      "} $alg');
    print('        senses: ${res.stream.map((r) => r.notation).join(' ')}');

    for (final (name, w) in [
      ('solve (wide+home+AS)',
          const BWeights(
              allowWide: true,
              softSegmentation: true,
              afterSlice: AfterSlice.fitted)),
      ('solve, no AS',
          const BWeights(allowWide: true, softSegmentation: true)),
      ('mistake (wides off)',
          const BWeights(allowWide: false, softSegmentation: true)),
    ]) {
      final b = methodBv2(res.stream, st, w,
          requireHomeDrift: name.startsWith('solve'));
      final hit = algToString(canonicalCollapsed(b.best)) ==
          algToString(canonicalCollapsed(truth));
      print('  [$name] ${hit ? "EXACT" : "WRONG"} '
          'margin ${b.margin.toStringAsFixed(2)}');
      for (final t in b.top.take(4)) {
        print('    +${t.$2.toStringAsFixed(2)}  ${t.$1}');
      }
    }
  }
}
