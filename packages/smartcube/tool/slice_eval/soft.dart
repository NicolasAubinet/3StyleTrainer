/// Hard vs soft segmentation, blind config, with a sweep over the timing
/// penalty and the abstention threshold (plan §31j).
///
/// The question this answers: soft segmentation makes the correct parse
/// REACHABLE when a slice's halves straddle kMotionGapMs, but it also lets the
/// search fuse turns that were genuinely separate. The adversarial group
/// (two-handed simultaneous outer pairs) is where that would show up.

import 'dart:math';
import 'algebra.dart';
import 'corpus.dart';
import 'methodb.dart';
import 'stats.dart';
import 'synth.dart';

final _c = <String, Stats>{};
Stats loo(String h) =>
    _c.putIfAbsent(h, () => Stats.fit(allAlgs().where((a) => a != h).toList()));

String cs(List<Move> a) => algToString(canonical(a));

class Score {
  int n = 0, ok = 0, kept = 0, keptOk = 0;
  final byGroup = <String, List<int>>{};
  double get exact => n == 0 ? 0 : 100 * ok / n;
  double get coverage => n == 0 ? 0 : 100 * kept / n;
  double get accuracy => kept == 0 ? 0 : 100 * keptOk / kept;
}

Score run(BWeights w, double abstain,
    {SynthConfig cfg = const SynthConfig(), int beam = 250}) {
  final s = Score();
  for (final g in corpus) {
    if (g.name == 'wide moves') continue;
    for (final algStr in g.algs) {
      final truth = parseAlg(algStr);
      final st = loo(algStr);
      for (var seed = 0; seed < 25; seed++) {
        final res =
            synthesize(truth, Random(seed * 7919 + algStr.hashCode), cfg);
        final b = methodBv2(res.stream, st, w, beam: beam);
        final hit = cs(b.best) == cs(truth);
        s.n++;
        if (hit) s.ok++;
        if (b.margin >= abstain) {
          s.kept++;
          if (hit) s.keptOk++;
        }
        final gs = s.byGroup.putIfAbsent(g.name, () => [0, 0]);
        gs[0]++;
        if (hit) gs[1]++;
      }
    }
  }
  return s;
}

String pc(num v) => v.toStringAsFixed(1);

const _clean = SynthConfig();

/// 25% of slices executed sloppily. The §31j capture had it on 5 takes out of
/// 5, but that is one alg the owner happens to fumble; a quarter of slices
/// across the whole corpus is the conservative reading.
const _sloppy = SynthConfig(pSloppySlice: 0.25);

void sweep(String title, SynthConfig cfg) {
  const base = BWeights(allowWide: false);
  print('\n== $title ==');
  print('config                  exact   cov@1.0  acc@1.0');
  final hard = run(base, 1.0, cfg: cfg);
  print('hard (shipped)          ${pc(hard.exact)}%   '
      '${pc(hard.coverage)}%    ${pc(hard.accuracy)}%');

  final softs = <double, Score>{};
  for (final tp in [0.5, 1.0, 1.5, 2.0, 3.0]) {
    final w = base.copyWith(softSegmentation: true, timingPenalty: tp);
    final s = run(w, 1.0, cfg: cfg);
    softs[tp] = s;
    print('soft tp=${tp.toStringAsFixed(2)}            ${pc(s.exact)}%   '
        '${pc(s.coverage)}%    ${pc(s.accuracy)}%');
  }

  print('-- per-group exact --');
  final cols = softs.keys.toList()..sort();
  print('${'group'.padRight(38)}${'hard'.padLeft(6)}'
      '${cols.map((t) => 'tp$t'.padLeft(7)).join()}');
  for (final g in hard.byGroup.keys) {
    final h = hard.byGroup[g]!;
    final row =
        StringBuffer('${g.padRight(38)}${pc(100 * h[1] / h[0]).padLeft(6)}');
    for (final t in cols) {
      final v = softs[t]!.byGroup[g]!;
      row.write(pc(100 * v[1] / v[0]).padLeft(7));
    }
    print(row);
  }
}

void main() {
  const base = BWeights(allowWide: false);
  sweep('clean slices (the ORIGINAL corpus — cannot represent the bug)', _clean);
  sweep('25% sloppy slices (models the measured failure)', _sloppy);

  // The abstain threshold is global; check 0.5 holds up on clean input too.
  print('\n== abstention on the CLEAN corpus (the regression risk) ==');
  print('config          threshold  coverage  accuracy');
  for (final th in [0.25, 0.5, 0.75, 1.0]) {
    final s = run(base.copyWith(softSegmentation: true, timingPenalty: 1.0), th,
        cfg: _clean);
    print('soft tp=1.0       ${th.toStringAsFixed(2)}      '
        '${pc(s.coverage).padLeft(6)}%   ${pc(s.accuracy).padLeft(6)}%');
  }
  for (final th in [0.5, 1.0]) {
    final s = run(base, th, cfg: _clean);
    print('hard (old)      ${th.toStringAsFixed(2)}      '
        '${pc(s.coverage).padLeft(6)}%   ${pc(s.accuracy).padLeft(6)}%');
  }

  print('\n== crossover: how rare must sloppy slices be for HARD to win? ==');
  print('pSloppy   hard   soft tp=1.0   soft tp=2.0');
  for (final p in [0.0, 0.02, 0.05, 0.10, 0.15, 0.25, 0.40]) {
    final cfg = SynthConfig(pSloppySlice: p);
    final h = run(base, 1.0, cfg: cfg);
    final s1 = run(
        base.copyWith(softSegmentation: true, timingPenalty: 1.0), 1.0,
        cfg: cfg);
    final s2 = run(
        base.copyWith(softSegmentation: true, timingPenalty: 2.0), 1.0,
        cfg: cfg);
    print('  ${p.toStringAsFixed(2)}    ${pc(h.exact).padLeft(5)}%   '
        '${pc(s1.exact).padLeft(5)}%        ${pc(s2.exact).padLeft(5)}%');
  }

  // NOTE: this table says beam width is free. It is not — see plan §31j; the
  // hardware fixture is what vetoes narrowing, and this corpus cannot see it.
  print('\n== beam sensitivity (soft tp=1.0, sloppy corpus) ==');
  print('beam    exact   cov@0.5  acc@0.5');
  for (final b in [250, 128, 64, 32, 16]) {
    final s = run(base.copyWith(softSegmentation: true, timingPenalty: 1.0), 0.5,
        cfg: _sloppy, beam: b);
    print('${b.toString().padLeft(4)}    ${pc(s.exact)}%   '
        '${pc(s.coverage)}%    ${pc(s.accuracy)}%');
  }

  print('\n== abstention sweep, sloppy corpus ==');
  print('config          threshold  coverage  accuracy');
  for (final tp in [1.0, 1.5, 2.0]) {
    for (final th in [0.25, 0.5, 0.75, 1.0]) {
      final s = run(base.copyWith(softSegmentation: true, timingPenalty: tp),
          th,
          cfg: _sloppy);
      print('soft tp=$tp       ${th.toStringAsFixed(2)}      '
          '${pc(s.coverage).padLeft(6)}%   ${pc(s.accuracy).padLeft(6)}%');
    }
  }
  for (final th in [0.5, 1.0]) {
    final s = run(base, th, cfg: _sloppy);
    print('hard            ${th.toStringAsFixed(2)}      '
        '${pc(s.coverage).padLeft(6)}%   ${pc(s.accuracy).padLeft(6)}%');
  }
}
