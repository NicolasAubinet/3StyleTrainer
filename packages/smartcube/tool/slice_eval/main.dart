/// Eval harness: synthesize reported streams from the corpus, run both
/// reconstruction methods, measure recovery. Stats are fitted leave-one-out.

import 'dart:math';
import 'algebra.dart';
import 'corpus.dart';
import 'methodb.dart';
import 'methods.dart';
import 'stats.dart';
import 'synth.dart';

const int kSeeds = 25;

String canonStr(List<Move> a) => algToString(canonical(a));

class Score {
  int trials = 0, exact = 0;
  int moveTotal = 0, moveOk = 0;
  int sliceTruth = 0, slicePred = 0, sliceHit = 0;

  void add(List<Move> truth, List<Move> pred) {
    final t = canonical(truth), p = canonical(pred);
    trials++;
    if (algToString(t) == algToString(p)) exact++;
    moveTotal += t.length;
    final n = min(t.length, p.length);
    for (var i = 0; i < n; i++) {
      if (t[i] == p[i]) moveOk++;
    }
    sliceTruth += t.where((m) => m.kind == MoveKind.slice).length;
    slicePred += p.where((m) => m.kind == MoveKind.slice).length;
    for (var i = 0; i < n; i++) {
      if (t[i].kind == MoveKind.slice && t[i] == p[i]) sliceHit++;
    }
  }

  String get line {
    String pc(num v) => v.toStringAsFixed(1).padLeft(5);
    final prec = slicePred == 0 ? '   - ' : pc(100 * sliceHit / slicePred);
    final rec = sliceTruth == 0 ? '   - ' : pc(100 * sliceHit / sliceTruth);
    return 'exact ${pc(100 * exact / max(trials, 1))}%  '
        'move ${pc(100 * moveOk / max(moveTotal, 1))}%  '
        'slice P $prec% R $rec%  (n=$trials)';
  }
}

/// Leave-one-out stats: fit on every alg except the one under test.
final _looCache = <String, Stats>{};
Stats looStats(String held) =>
    _looCache.putIfAbsent(held, () => Stats.fit(allAlgs().where((a) => a != held).toList()));

void main() {
  print('=' * 78);
  print('SLICE / WIDE RECONSTRUCTION — synthetic eval');
  print('corpus: ${allAlgs().length} algs x $kSeeds seeds  (stats fitted leave-one-out)');
  print('=' * 78);
  corpusStats();
  print('');
  runMethods();
  print('');
  ablations();
  print('');
  abstentionCurve();
}

void corpusStats() {
  print('\n-- 1. "slices are rarely followed by F/B" — measured on the corpus --');
  final overall = List<int>.filled(6, 0);
  final afterSlice = List<int>.filled(6, 0);
  final afterOuterPair = List<int>.filled(6, 0);
  for (final s in allAlgs()) {
    final alg = parseAlg(s);
    for (var i = 0; i < alg.length; i++) {
      final m = alg[i];
      if (m.kind == MoveKind.outer) overall[m.id]++;
      if (i + 1 < alg.length && alg[i + 1].kind == MoveKind.outer) {
        if (m.kind == MoveKind.slice) afterSlice[alg[i + 1].id]++;
        if (m.kind == MoveKind.outer &&
            i > 0 &&
            alg[i - 1].kind == MoveKind.outer &&
            oppositeFace[alg[i - 1].id] == m.id) {
          afterOuterPair[alg[i + 1].id]++;
        }
      }
    }
  }
  void show(String label, List<int> c) {
    final tot = c.reduce((a, b) => a + b);
    if (tot == 0) return print('  ${label.padRight(24)} (no samples)');
    final parts = [
      for (var f = 0; f < 6; f++)
        '${faceNames[f]} ${(100 * c[f] / tot).toStringAsFixed(0).padLeft(2)}%'
    ];
    final fb = 100 * (c[F] + c[B]) / tot;
    print('  ${label.padRight(24)} ${parts.join('  ')}  | F+B ${fb.toStringAsFixed(1)}%  (n=$tot)');
  }

  show('all outer moves', overall);
  show('move after a slice', afterSlice);
  show('move after an outer pair', afterOuterPair);
  print('\n  fitted costs (full corpus):\n  ${Stats.fit(allAlgs()).describe()}');
}

void runMethods() {
  print('-- 2. Reconstruction accuracy --');
  const bw = BWeights();
  final totals = {'A-timing': Score(), 'A-rule': Score(), 'B': Score()};

  for (final g in corpus) {
    final a = Score(), aT = Score(), b = Score();
    for (final algStr in g.algs) {
      final truth = parseAlg(algStr);
      final st = looStats(algStr);
      for (var seed = 0; seed < kSeeds; seed++) {
        final res = synthesize(truth, Random(seed * 7919 + algStr.hashCode));
        final pa = methodA(res.stream);
        final pt = methodA(res.stream, const MethodAConfig(useFollowingMoveTest: false));
        final pb = methodBv2(res.stream, st, bw).best;
        a.add(truth, pa);
        aT.add(truth, pt);
        b.add(truth, pb);
        totals['A-rule']!.add(truth, pa);
        totals['A-timing']!.add(truth, pt);
        totals['B']!.add(truth, pb);
      }
    }
    print('\n  ${g.name}');
    print('    A (timing only)       ${aT.line}');
    print('    A (+ following-move)  ${a.line}');
    print('    B (beam + structure)  ${b.line}');
  }
  print('\n  ALL');
  print('    A (timing only)       ${totals['A-timing']!.line}');
  print('    A (+ following-move)  ${totals['A-rule']!.line}');
  print('    B (beam + structure)  ${totals['B']!.line}');
}

void ablations() {
  print('-- 3. Method B ablations --');
  const base = BWeights();
  final variants = <String, BWeights>{
    'full (tuned)': base,
    'no conjugate bonus': base.copyWith(conjugateBonus: 0.0),
    'no face prior': base.copyWith(useFacePrior: false),
    '+ after-slice (fitted)': base.copyWith(afterSlice: AfterSlice.fitted),
    '+ after-slice (binary)': base.copyWith(afterSlice: AfterSlice.binary),
    'no drift penalty': base.copyWith(driftPenalty: 0.0),
    'hard drift constraint': base.copyWith(driftPenalty: 1000.0),
    'no wides allowed': base.copyWith(allowWide: false),
  };
  variants.forEach((name, w) {
    final s = Score();
    for (final algStr in allAlgs()) {
      final truth = parseAlg(algStr);
      final st = looStats(algStr);
      for (var seed = 0; seed < kSeeds; seed++) {
        final res = synthesize(truth, Random(seed * 7919 + algStr.hashCode));
        s.add(truth, methodBv2(res.stream, st, w).best);
      }
    }
    print('    ${name.padRight(24)} ${s.line}');
  });
}

void abstentionCurve() {
  print('-- 4. Method B abstention (margin threshold) --');
  const w = BWeights();
  for (final thr in [0.0, 0.5, 1.0, 2.0, 3.0]) {
    var n = 0, kept = 0, keptOk = 0;
    for (final algStr in allAlgs()) {
      final truth = parseAlg(algStr);
      final st = looStats(algStr);
      for (var seed = 0; seed < kSeeds; seed++) {
        final res = synthesize(truth, Random(seed * 7919 + algStr.hashCode));
        final r = methodBv2(res.stream, st, w);
        n++;
        if (r.margin >= thr) {
          kept++;
          if (canonStr(r.best) == canonStr(truth)) keptOk++;
        }
      }
    }
    print('    margin >= ${thr.toStringAsFixed(1)}  '
        'coverage ${(100 * kept / n).toStringAsFixed(1).padLeft(5)}%  '
        'accuracy-when-answered ${(kept == 0 ? 0 : 100 * keptOk / kept).toStringAsFixed(1).padLeft(5)}%');
  }
}
