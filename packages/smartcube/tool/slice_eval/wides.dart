/// Wide moves in the hypothesis space, with the solves-close-home constraint
/// (plan §31k). Compares wides off / on / on+home per corpus group.
///
/// NOTE: adding the 'blind wides (blddb)' group changed Stats.fit for every
/// alg, so numbers here are not comparable to sweeps run before it existed —
/// compare only within this run's own baseline column.

import 'dart:math';
import 'algebra.dart';
import 'corpus.dart';
import 'methodb.dart';
import 'stats.dart';
import 'synth.dart';

// Fit on the ORIGINAL corpus only. The shipped lib uses fixed weights
// transcribed from that fit, so the shipping decision must hold the prior
// constant and vary only the hypothesis space. (Refitting WITH the blddb group
// shifts the prior enough to cost the adversarial group ~11 points by itself —
// measured 2026-07-21 — which is §31i.G's corpus-sensitivity, a separate
// decision from wides.)
final _fitBase = [
  for (final g in corpus)
    if (g.name != 'blind wides (blddb)') ...g.algs
];
final _c = <String, Stats>{};
Stats loo(String h) =>
    _c.putIfAbsent(h, () => Stats.fit(_fitBase.where((a) => a != h).toList()));

String cs(List<Move> a) => algToString(canonical(a));

class Cfg {
  final String name;
  final bool wide;
  final bool home;
  const Cfg(this.name, this.wide, this.home);
}

const cfgs = [
  Cfg('off', false, false),
  Cfg('wide', true, false),
  Cfg('wide+home', true, true),
];

void main() {
  // [exact ok, n, answered, answered ok]
  final perGroup = <String, Map<String, List<int>>>{};

  for (final g in corpus) {
    for (final algStr in g.algs) {
      final truth = parseAlg(algStr);
      final st = loo(algStr);
      for (var seed = 0; seed < 25; seed++) {
        final res = synthesize(truth, Random(seed * 7919 + algStr.hashCode));
        for (final c in cfgs) {
          final w = BWeights(allowWide: c.wide, softSegmentation: true);
          final b = methodBv2(res.stream, st, w, requireHomeDrift: c.home);
          final hit = cs(b.best) == cs(truth);
          final gg = perGroup.putIfAbsent(g.name, () => {})
              .putIfAbsent(c.name, () => [0, 0, 0, 0]);
          gg[1]++;
          if (hit) gg[0]++;
          if (b.margin >= 0.5) {
            gg[2]++;
            if (hit) gg[3]++;
          }
        }
      }
    }
  }

  String pc(int ok, int n) =>
      n == 0 ? '    -' : (100 * ok / n).toStringAsFixed(1).padLeft(5);
  print('== per group: exact | answered-accuracy@0.5 (n=25 seeds/alg) ==');
  print('(home column is only meaningful for groups whose algs close the '
      'frame — the trainer asserts it on completed solves only)');
  print('${'group'.padRight(40)}${cfgs.map((c) => c.name.padLeft(16)).join()}');
  perGroup.forEach((g, m) {
    final row = StringBuffer(g.padRight(40));
    for (final c in cfgs) {
      final v = m[c.name]!;
      row.write('${pc(v[0], v[1])}|${pc(v[3], v[2])}'.padLeft(16));
    }
    print(row);
  });
}
