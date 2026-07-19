/// The practical configuration: blind solving, where wide moves are rare
/// enough to leave out of the hypothesis space entirely.

import 'dart:math';
import 'algebra.dart';
import 'corpus.dart';
import 'methodb.dart';
import 'methods.dart';
import 'stats.dart';
import 'synth.dart';

final _c = <String, Stats>{};
Stats loo(String h) =>
    _c.putIfAbsent(h, () => Stats.fit(allAlgs().where((a) => a != h).toList()));


String cs(List<Move> a) => algToString(canonical(a));

void main() {
  final blindAlgs = [
    for (final g in corpus)
      if (g.name != 'wide moves') ...g.algs
  ];
  const w = BWeights(allowWide: false);

  var n = 0, okB = 0, okA = 0, okT = 0;
  var kept = 0, keptOk = 0;
  for (final algStr in blindAlgs) {
    final truth = parseAlg(algStr);
    final st = loo(algStr);
    for (var seed = 0; seed < 25; seed++) {
      final res = synthesize(truth, Random(seed * 7919 + algStr.hashCode));
      n++;
      final b = methodBv2(res.stream, st, w);
      if (cs(b.best) == cs(truth)) okB++;
      if (cs(methodA(res.stream)) == cs(truth)) okA++;
      if (cs(methodA(res.stream, const MethodAConfig(useFollowingMoveTest: false))) ==
          cs(truth)) okT++;
      if (b.margin >= 1.0) {
        kept++;
        if (cs(b.best) == cs(truth)) keptOk++;
      }
    }
  }
  String pc(num v) => v.toStringAsFixed(1);
  print('blind configuration (wide moves excluded), ${blindAlgs.length} algs, n=$n');
  print('  A (timing only)       ${pc(100 * okT / n)}%');
  print('  A (+ following-move)  ${pc(100 * okA / n)}%');
  print('  B (beam, no wides)    ${pc(100 * okB / n)}%');
  print('  B @ margin>=1.0       coverage ${pc(100 * kept / n)}%  '
      'accuracy ${pc(100 * keptOk / kept)}%');
}
