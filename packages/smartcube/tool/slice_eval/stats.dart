/// Corpus statistics, fitted leave-one-out so no alg is scored with a model
/// that saw it. All costs are negative log probabilities (add-1 smoothed).

import 'dart:math';
import 'algebra.dart';
import 'synth.dart';

class Stats {
  final List<double> faceCost; // outer move face
  final double outerCost, sliceCost, wideCost;
  final double halfCost, quarterCost;

  /// -log P(next outer face | previous move was a slice)
  final List<double> afterSliceFaceCost;

  const Stats(this.faceCost, this.outerCost, this.sliceCost, this.wideCost,
      this.halfCost, this.quarterCost, this.afterSliceFaceCost);

  static Stats fit(List<String> algs) =>
      fitWeighted([for (final s in algs) (parseAlg(s), 1.0)]);

  /// Fit from parsed algs with per-alg weights (e.g. blddb user counts).
  static Stats fitWeighted(List<(List<Move>, double)> algs) {
    final face = List<double>.filled(6, 1.0);
    final afterSlice = List<double>.filled(6, 1.0);
    var outer = 1.0, slice = 1.0, wide = 1.0, half = 1.0, quarter = 1.0;

    for (final (alg, wt) in algs) {
      for (var i = 0; i < alg.length; i++) {
        final m = alg[i];
        switch (m.kind) {
          case MoveKind.outer:
            outer += wt;
            face[m.id] += wt;
            break;
          case MoveKind.slice:
            slice += wt;
            break;
          case MoveKind.wide:
            wide += wt;
            break;
          case MoveKind.rotation:
            break;
        }
        if (m.amount == 2) {
          half += wt;
        } else {
          quarter += wt;
        }
        if (i > 0 && alg[i - 1].kind == MoveKind.slice && m.kind == MoveKind.outer) {
          afterSlice[m.id] += wt;
        }
      }
    }

    double nlog(double c, double tot) => -log(c / tot);

    final faceTot = face.reduce((a, b) => a + b);
    final kindTot = outer + slice + wide;
    final amtTot = half + quarter;
    final asTot = afterSlice.reduce((a, b) => a + b);

    return Stats(
      [for (final c in face) nlog(c, faceTot)],
      nlog(outer, kindTot),
      nlog(slice, kindTot),
      nlog(wide, kindTot),
      nlog(half, amtTot),
      nlog(quarter, amtTot),
      [for (final c in afterSlice) nlog(c, asTot)],
    );
  }

  String describe() {
    String f(double v) => v.toStringAsFixed(2);
    return 'face[U D L R F B] = ${faceCost.map(f).join(' ')}\n'
        '  kind: outer ${f(outerCost)}  slice ${f(sliceCost)}  wide ${f(wideCost)}'
        '  half ${f(halfCost)}  quarter ${f(quarterCost)}\n'
        '  afterSlice[U D L R F B] = ${afterSliceFaceCost.map(f).join(' ')}';
  }
}
