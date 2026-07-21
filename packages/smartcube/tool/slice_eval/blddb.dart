/// Fit the reconstruction prior from blddb's manmade alg database
/// (github.com/nbwzx/blddb, branch v2, GPL-3.0) instead of the hand-written
/// corpus — the §31i.G refit.
///
/// Data files live in tool/slice_eval/data/ (gitignored), fetched from
/// https://v2.blddb.net/data/{edge,corner,flips}Manmade.json. Format per case:
/// speffz triple -> entries of [[alg variants], [users], (shorthand)]. An
/// entry's weight is its user count — "most used" — split evenly across its
/// parseable variants. Algs containing x/y/z rotations are excluded: a
/// rotation emits nothing, so no parse of a sensed stream can contain one.

import 'dart:convert';
import 'dart:io';

import 'algebra.dart';
import 'stats.dart';
import 'synth.dart';

class BlddbFit {
  final Stats stats;
  final int entries, variantsUsed, variantsSkipped;
  final double totalWeight;
  const BlddbFit(this.stats, this.entries, this.variantsUsed,
      this.variantsSkipped, this.totalWeight);

  String describe() =>
      'blddb: $entries entries, $variantsUsed alg variants used '
      '($variantsSkipped skipped: rotation/unparseable), '
      'total user weight ${totalWeight.toStringAsFixed(0)}\n'
      '  ${stats.describe()}';
}

const _files = ['edgeManmade.json', 'cornerManmade.json', 'flipsManmade.json'];

BlddbFit fitBlddb({String dir = 'tool/slice_eval/data'}) {
  final weighted = <(List<Move>, double)>[];
  var entries = 0, used = 0, skipped = 0;
  var totalW = 0.0;
  final unparseable = <String, int>{};

  for (final name in _files) {
    final map =
        jsonDecode(File('$dir/$name').readAsStringSync()) as Map<String, dynamic>;
    for (final caseEntries in map.values) {
      for (final e in caseEntries as List) {
        entries++;
        final users = (e[1] as List).length;
        if (users == 0) continue;
        final variants = <List<Move>>[];
        for (final a in (e[0] as List).cast<String>()) {
          List<Move> parsed;
          try {
            parsed = parseAlg(a);
          } catch (_) {
            skipped++;
            unparseable.putIfAbsent(a, () => 0);
            unparseable[a] = unparseable[a]! + 1;
            continue;
          }
          if (parsed.any((m) => m.kind == MoveKind.rotation)) {
            skipped++;
            continue;
          }
          variants.add(parsed);
        }
        if (variants.isEmpty) continue;
        final w = users / variants.length;
        for (final v in variants) {
          weighted.add((v, w));
          used++;
          totalW += w;
        }
      }
    }
  }
  if (unparseable.isNotEmpty) {
    final top = unparseable.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    stderr.writeln('unparseable: ${unparseable.length} distinct, e.g. '
        '${top.take(8).map((e) => '"${e.key}"').join(', ')}');
  }
  return BlddbFit(Stats.fitWeighted(weighted), entries, used, skipped, totalW);
}

void main() {
  final fit = fitBlddb();
  print(fit.describe());
  final st = fit.stats;
  String f(double v) => v.toStringAsFixed(4);
  print('\n// ReconstructionWeights transcription:');
  print('faceCost = const [${st.faceCost.map(f).join(', ')}],');
  print('outerCost = ${f(st.outerCost)},');
  print('sliceCost = ${f(st.sliceCost)},');
  print('wideCost = ${f(st.wideCost)},');
  print('halfCost = ${f(st.halfCost)},');
  print('quarterCost = ${f(st.quarterCost)},');
  print('afterSliceFaceCost = const [${st.afterSliceFaceCost.map(f).join(', ')}],');
}
