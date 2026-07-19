/// Qualitative check: the owner's counterexample, its slice twin, and a dump of
/// Method B's remaining failure modes.

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

void main() {
  print('-- the counterexample and its twin --\n');
  for (final algStr in [
    "R U D' R'",
    "R E R'",
    "R U D' R' F' R U R' U' R' F R2 U' R' U' R D R'",
    "M' U R U' M U R' U'",
    "Rw U R' U' Rw' F R F'",
  ]) {
    final truth = parseAlg(algStr);
    // force the two-handed simultaneous execution so the timing is identical
    final res = synthesize(truth, Random(3),
        const SynthConfig(pSimultaneousOuterPair: 1.0));
    final raw = res.stream.map((r) => r.notation).join(' ');
    final b = methodBv2(res.stream, loo(algStr), const BWeights());
    final ok = cs(b.best) == cs(truth) ? 'OK ' : 'BAD';
    print('  truth     $algStr');
    print('  reported  $raw');
    print('  $ok recon ${algToString(b.best)}   (margin ${b.margin.toStringAsFixed(2)})');
    print('');
  }

  print('-- remaining Method B failures --\n');
  final byKind = <String, int>{};
  var shown = 0;
  for (final g in corpus) {
    for (final algStr in g.algs) {
      final truth = parseAlg(algStr);
      final st = loo(algStr);
      for (var seed = 0; seed < 25; seed++) {
        final res = synthesize(truth, Random(seed * 7919 + algStr.hashCode));
        final b = methodBv2(res.stream, st, const BWeights());
        if (cs(b.best) == cs(truth)) continue;
        byKind[g.name] = (byKind[g.name] ?? 0) + 1;
        if (shown < 8) {
          shown++;
          print('  [${g.name}]');
          print('    truth ${cs(truth)}');
          print('    got   ${cs(b.best)}  (margin ${b.margin.toStringAsFixed(2)})');
        }
      }
    }
  }
  print('\n  failures by group:');
  byKind.forEach((k, v) => print('    ${k.padRight(40)} $v'));
}
