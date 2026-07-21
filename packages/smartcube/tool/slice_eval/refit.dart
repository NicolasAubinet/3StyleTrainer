/// The §31i.G refit sweep: corpus-fitted prior (shipped) vs blddb-fitted
/// prior, on both trainer paths — mistake replays (wides off, no home
/// constraint, abstain 0.5) and solve replays (wides on, home required,
/// abstain 0.75). Prints per-group exact rates and the margin bands needed to
/// retune the abstain thresholds: any prior change shifts them (§31j).
///
/// The 'blind wides (blddb)' group is fit-contaminated under the blddb prior
/// (those 16 algs are in the database); treat its blddb column as optimistic.
/// The base prior is leave-one-out over the original corpus, matching
/// wides.dart.

import 'dart:math';

import 'algebra.dart';
import 'blddb.dart';
import 'corpus.dart';
import 'methodb.dart';
import 'stats.dart';
import 'synth.dart';

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
  final bool wide, home;
  final AfterSlice afterSlice;
  const Cfg(this.name, this.wide, this.home,
      [this.afterSlice = AfterSlice.off]);
}

// The +AS variants re-test §31f's rejected "slice is rarely followed by F/B"
// term: rejected when fitted from n=58 corpus transitions, re-tried now that
// blddb estimates the after-slice distribution from ~87k weighted moves.
const cfgs = [
  Cfg('mistake', false, false), // wides off — the mistake-replay path
  Cfg('mist+AS', false, false, AfterSlice.fitted),
  Cfg('solve', true, true), // wides + closed drift — the solve path
  Cfg('solve+AS', true, true, AfterSlice.fitted),
];

// (A 50/50 probability-space blend of corpus+blddb priors was swept 2026-07-21
// and bought nothing over pure blddb — removed rather than kept as a dead knob.)

void main() {
  final blddb = fitBlddb();
  print(blddb.describe());
  print('corpus (shipped fit): ${Stats.fit(_fitBase).describe()}');
  print('');

  // group -> config+prior -> [exact, n]
  final perGroup = <String, Map<String, List<int>>>{};
  // group -> config+prior -> list of (margin, hit)
  final margins = <String, Map<String, List<(double, bool)>>>{};

  for (final g in corpus) {
    for (final algStr in g.algs) {
      final truth = parseAlg(algStr);
      final priors = {
        'base': loo(algStr),
        'blddb': blddb.stats,
      };
      for (var seed = 0; seed < 25; seed++) {
        final res = synthesize(truth, Random(seed * 7919 + algStr.hashCode));
        for (final c in cfgs) {
          final w = BWeights(
              allowWide: c.wide,
              softSegmentation: true,
              afterSlice: c.afterSlice);
          priors.forEach((pName, st) {
            // The fitted after-slice term is only meaningful with a prior
            // whose estimate is real; the corpus fit's n=58 is not (§31f).
            if (c.afterSlice == AfterSlice.fitted && pName != 'blddb') return;
            final key = '${c.name}/$pName';
            final b = methodBv2(res.stream, st, w, requireHomeDrift: c.home);
            final hit = cs(b.best) == cs(truth);
            final gg = perGroup
                .putIfAbsent(g.name, () => {})
                .putIfAbsent(key, () => [0, 0]);
            gg[1]++;
            if (hit) gg[0]++;
            margins
                .putIfAbsent(g.name, () => {})
                .putIfAbsent(key, () => [])
                .add((b.margin, hit));
          });
        }
      }
    }
  }

  final keys = [
    for (final c in cfgs)
      ...[
        if (c.afterSlice == AfterSlice.off) '${c.name}/base',
        '${c.name}/blddb',
      ]
  ];
  String pc(int ok, int n) =>
      n == 0 ? '    -' : (100 * ok / n).toStringAsFixed(1).padLeft(5);
  print('== exact rate per group (25 seeds/alg) ==');
  print('${'group'.padRight(40)}${keys.map((k) => k.padLeft(14)).join()}');
  perGroup.forEach((g, m) {
    final row = StringBuffer(g.padRight(40));
    for (final k in keys) {
      final v = m[k] ?? [0, 0];
      row.write(pc(v[0], v[1]).padLeft(14));
    }
    print(row);
  });

  // The numbers that decide the abstain thresholds: per group, at each
  // candidate threshold, what fraction is answered and how often the answer is
  // right. The bar is "never confidently wrong" — a group may decline, it may
  // not answer wrongly at high margin.
  const thresholds = [0.5, 0.75, 1.0];
  for (final k in keys) {
    print('\n== $k: per-group coverage|acc at thresholds '
        '${thresholds.map((t) => t.toStringAsFixed(2)).join(' / ')} ==');
    margins.forEach((g, m) {
      final ms = m[k];
      if (ms == null) return;
      final row = StringBuffer(g.padRight(40));
      for (final t in thresholds) {
        final answered = ms.where((x) => x.$1 >= t).toList();
        final okAns = answered.where((x) => x.$2).length;
        row.write('${pc(answered.length, ms.length)}|${pc(okAns, answered.length)}'
            .padLeft(14));
      }
      print(row);
    });
  }
}
