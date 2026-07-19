/// How badly does the method degrade when timing is unreliable?
///
/// This needs no hardware and predicts the GoCube case (§30): no per-move cube
/// clock, moves batched into one notification share a stamp.

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

List<Move> canon(List<Move> alg) {
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

String cs(List<Move> a) => algToString(canon(a));

void main() {
  final blind = [
    for (final g in corpus)
      if (g.name != 'wide moves') ...g.algs
  ];
  const w = BWeights(allowWide: false);

  print('timing degradation (blind config, ${blind.length} algs x 25 seeds)');
  print('');
  print('  ${"condition".padRight(34)} ${"A-rule".padLeft(7)} ${"B".padLeft(7)}  '
      '${"B@margin>=1".padLeft(12)} ${"cov".padLeft(6)}');

  void run(String name, SynthConfig cfg) {
    var n = 0, okA = 0, okB = 0, kept = 0, keptOk = 0;
    for (final algStr in blind) {
      final truth = parseAlg(algStr);
      final st = loo(algStr);
      for (var seed = 0; seed < 25; seed++) {
        final res = synthesize(truth, Random(seed * 7919 + algStr.hashCode), cfg);
        n++;
        if (cs(methodA(res.stream)) == cs(truth)) okA++;
        final b = methodBv2(res.stream, st, w);
        final good = cs(b.best) == cs(truth);
        if (good) okB++;
        if (b.margin >= 1.0) {
          kept++;
          if (good) keptOk++;
        }
      }
    }
    String p(num v) => '${v.toStringAsFixed(1)}%';
    print('  ${name.padRight(34)} ${p(100 * okA / n).padLeft(7)} '
        '${p(100 * okB / n).padLeft(7)}  '
        '${(kept == 0 ? "-" : p(100 * keptOk / kept)).padLeft(12)} '
        '${p(100 * kept / n).padLeft(6)}');
  }

  run('exact clocks (baseline)', const SynthConfig());
  run('jitter +/-10ms', const SynthConfig(jitterMs: 10));
  run('jitter +/-25ms', const SynthConfig(jitterMs: 25));
  run('jitter +/-50ms', const SynthConfig(jitterMs: 50));
  run('quantized 20ms', const SynthConfig(quantizeMs: 20));
  run('quantized 50ms', const SynthConfig(quantizeMs: 50));
  run('quantized 100ms (GoCube-like)', const SynthConfig(quantizeMs: 100));
  run('quantized 200ms', const SynthConfig(quantizeMs: 200));
  run('quantized 100ms + jitter 25', const SynthConfig(quantizeMs: 100, jitterMs: 25));
}
