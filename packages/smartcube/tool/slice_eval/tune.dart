/// Hyperparameter sweep on a DEV split, then a single report on the held-out
/// TEST split, so the headline number is not tuned on itself.

import 'dart:math';
import 'algebra.dart';
import 'corpus.dart';
import 'methodb.dart';
import 'methods.dart';
import 'stats.dart';
import 'synth.dart';

const int kSeeds = 25;

List<Move> canonical(List<Move> alg) {
  final out = List<Move>.from(alg);
  for (var i = 0; i + 1 < out.length; i++) {
    final a = out[i], b = out[i + 1];
    if (a.kind == MoveKind.outer &&
        b.kind == MoveKind.outer &&
        oppositeFace[a.id] == b.id &&
        a.id > b.id) {
      out[i] = b;
      out[i + 1] = a;
    }
  }
  return out;
}

String cs(List<Move> a) => algToString(canonical(a));

(List<String>, List<String>) split() {
  final dev = <String>[], test = <String>[];
  for (final g in corpus) {
    for (var i = 0; i < g.algs.length; i++) {
      (i.isEven ? dev : test).add(g.algs[i]);
    }
  }
  return (dev, test);
}

final _cache = <String, Stats>{};
Stats loo(String held) =>
    _cache.putIfAbsent(held, () => Stats.fit(allAlgs().where((a) => a != held).toList()));

double evalOn(List<String> algs, BWeights w) {
  var n = 0, ok = 0;
  for (final algStr in algs) {
    final truth = parseAlg(algStr);
    final st = loo(algStr);
    for (var seed = 0; seed < kSeeds; seed++) {
      final res = synthesize(truth, Random(seed * 7919 + algStr.hashCode));
      n++;
      if (cs(methodBv2(res.stream, st, w).best) == cs(truth)) ok++;
    }
  }
  return 100.0 * ok / n;
}

void main() {
  final (dev, test) = split();
  print('dev ${dev.length} algs / test ${test.length} algs');
  print('');
  print('-- sweep on DEV --');

  BWeights? best;
  var bestScore = -1.0;
  for (final af in AfterSlice.values) {
    for (final dp in [0.0, 1.0, 2.0, 4.0, 8.0]) {
      for (final cj in [0.0, 0.5, 1.0]) {
        final w = BWeights(afterSlice: af, driftPenalty: dp, conjugateBonus: cj);
        final s = evalOn(dev, w);
        if (s > bestScore) {
          bestScore = s;
          best = w;
        }
      }
    }
  }
  // Report the sweep marginals for readability.
  for (final af in AfterSlice.values) {
    final w = best!.copyWith(afterSlice: af);
    print('  afterSlice=${af.name.padRight(7)} dev ${evalOn(dev, w).toStringAsFixed(1)}%');
  }
  for (final dp in [0.0, 1.0, 2.0, 4.0, 8.0]) {
    final w = best!.copyWith(driftPenalty: dp);
    print('  driftPenalty=${dp.toStringAsFixed(1).padLeft(4)}  dev ${evalOn(dev, w).toStringAsFixed(1)}%');
  }
  for (final cj in [0.0, 0.5, 1.0]) {
    final w = best!.copyWith(conjugateBonus: cj);
    print('  conjugate=${cj.toStringAsFixed(1)}      dev ${evalOn(dev, w).toStringAsFixed(1)}%');
  }

  print('');
  print('BEST on dev: afterSlice=${best!.afterSlice.name} '
      'driftPenalty=${best.driftPenalty} conjugate=${best.conjugateBonus} '
      '-> dev ${bestScore.toStringAsFixed(1)}%');
  print('');
  print('-- held-out TEST --');
  print('  B (tuned)            ${evalOn(test, best).toStringAsFixed(1)}%');

  // Method A on the same test split, for comparison.
  var n = 0, okA = 0, okT = 0;
  for (final algStr in test) {
    final truth = parseAlg(algStr);
    for (var seed = 0; seed < kSeeds; seed++) {
      final res = synthesize(truth, Random(seed * 7919 + algStr.hashCode));
      n++;
      if (cs(methodA(res.stream)) == cs(truth)) okA++;
      if (cs(methodA(res.stream, const MethodAConfig(useFollowingMoveTest: false))) ==
          cs(truth)) okT++;
    }
  }
  print('  A (timing only)      ${(100.0 * okT / n).toStringAsFixed(1)}%');
  print('  A (+ following-move) ${(100.0 * okA / n).toStringAsFixed(1)}%');
}
