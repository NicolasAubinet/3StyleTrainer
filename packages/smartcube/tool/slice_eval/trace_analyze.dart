/// Offline analysis of captured hardware traces (JSONL from the example app's
/// §31 validation page → Trace capture).
///
///   dart run trace_analyze.dart ../../../../cube_traces/trace_*.jsonl
///
/// The question it answers: **does motion segmentation survive real timing?**
/// Everything in the §31 eval is gated on gaps between separate motions being
/// cleanly separable from spreads within one motion. If the histogram below is
/// bimodal with an empty valley, segmentation works. If it is smeared, the
/// timing gate is unreliable on this cube and the method needs re-tuning (or
/// abstention has to carry more).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'algebra.dart';
import 'methodb.dart';
import 'stats.dart';
import 'synth.dart';
import 'corpus.dart';

class Row {
  final String label;
  final int take;
  final int face;
  final bool prime;
  final int cubeMs;
  final int? hostMs;
  Row(this.label, this.take, this.face, this.prime, this.cubeMs, this.hostMs);
}

void main(List<String> args) {
  if (args.isEmpty) {
    print('usage: dart run trace_analyze.dart <trace.jsonl> [more.jsonl ...]');
    exit(2);
  }
  final rows = <Row>[];
  for (final path in args) {
    final f = File(path);
    if (!f.existsSync()) {
      stderr.writeln('missing: $path');
      continue;
    }
    for (final line in f.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final j = jsonDecode(line) as Map<String, dynamic>;
      rows.add(Row(
        (j['label'] as String?) ?? '',
        (j['take'] as int?) ?? 0,
        faceNames.indexOf(j['face'] as String),
        j['prime'] as bool,
        j['cubeMs'] as int,
        j['hostMs'] as int?,
      ));
    }
  }
  if (rows.isEmpty) {
    print('no rows');
    exit(1);
  }
  // Save writes the whole buffer each time, so saving twice mid-session
  // produces files that overlap. A row is uniquely identified by its take and
  // cube timestamp, so exact duplicates are always spurious — drop them and
  // the glob is safe however many times the operator hit Save.
  final seen = <String>{};
  final deduped = <Row>[];
  for (final r in rows) {
    if (seen.add('${r.label}|${r.take}|${r.face}|${r.prime}|${r.cubeMs}')) {
      deduped.add(r);
    }
  }
  final dropped = rows.length - deduped.length;
  rows
    ..clear()
    ..addAll(deduped);
  print('loaded ${rows.length} moves from ${args.length} file(s)'
      '${dropped > 0 ? "  (dropped $dropped duplicate rows from overlapping saves)" : ""}');

  // Key by (label, take): each Record press is a separate execution, so
  // repeating an alg gives independent sequences rather than one merged stream.
  final byTake = <String, List<Row>>{};
  for (final r in rows) {
    byTake.putIfAbsent('${r.label}#${r.take}', () => []).add(r);
  }
  print('labelled takes: ${byTake.length}');
  print('');

  _gapHistogram(byTake);
  print('');
  _completeness(byTake);
  print('');
  _executionCheck(byTake);
  print('');
  _reconstruct(byTake);
}

/// The reported quarter turns the labelled alg SHOULD produce, given the cube
/// started in orientation [rho0]. Pure §31a — no timing, no heuristics.
/// `half` marks turns emitted by a HALF turn. A 180 degree turn has no
/// canonical direction — the cube reports whichever way it was physically
/// spun — so those turns are compared on face only.
typedef PredTurn = ({int face, bool prime, bool half});

List<PredTurn> predictStream(List<Move> alg, List<int> rho0) {
  var rho = rho0;
  final out = <PredTurn>[];
  for (final m in alg) {
    final dec = decompose(m);
    final inv = invert(rho);
    for (final s in dec.sensed) {
      final f = inv[s.face];
      if (s.amount == 2) {
        out.add((face: f, prime: false, half: true));
        out.add((face: f, prime: false, half: true));
      } else {
        out.add((face: f, prime: s.amount == 3, half: false));
      }
    }
    rho = compose(dec.drift, rho);
  }
  return out;
}

/// Order-free: were the right turns executed at all, however they were grouped
/// into motions? An `M2` done as two separate `M` turns passes this but not
/// [_compareWindows] — correct execution, different phrasing.
int _compareBag(List<Row> rows, List<PredTurn> pred) {
  if (rows.length != pred.length) return 1 << 30;
  final avail = pred.toList();
  var miss = 0;
  for (final r in rows) {
    final hit = avail
        .indexWhere((p) => p.face == r.face && (p.half || p.prime == r.prime));
    if (hit < 0) {
      miss++;
    } else {
      avail.removeAt(hit);
    }
  }
  return miss;
}

/// Turns inside one physical motion reach the cube in an arbitrary order, so
/// compare each motion as a MULTISET, not a sequence. Returns the number of
/// turns that cannot be matched.
int _compareWindows(List<Row> rows, List<PredTurn> pred) {
  if (rows.length != pred.length) return 1 << 30;
  var miss = 0, i = 0;
  while (i < rows.length) {
    // One motion = turns within 60ms of the previous one (§31g histogram).
    var j = i + 1;
    while (j < rows.length && rows[j].cubeMs - rows[j - 1].cubeMs <= 60) {
      j++;
    }
    final avail = pred.sublist(i, j).toList();
    for (var k = i; k < j; k++) {
      final r = rows[k];
      final hit = avail.indexWhere(
          (p) => p.face == r.face && (p.half || p.prime == r.prime));
      if (hit < 0) {
        miss++;
      } else {
        avail.removeAt(hit);
      }
    }
    i = j;
  }
  return miss;
}

/// ★ Separates "the method got it wrong" from "the cube was not doing what the
/// label says". For each take, find the initial orientation that best explains
/// the stream, and count how many turns still disagree.
void _executionCheck(Map<String, List<Row>> byTake) {
  print('-- execution check: does each take match its label? --');
  final group = buildRotationGroup();
  var clean = 0, total = 0, regrouped = 0;
  final orientations = <String, int>{};

  byTake.forEach((key, rows) {
    final label = _algOf(key);
    if (label.isEmpty) return;
    List<Move> alg;
    try {
      alg = parseAlg(label);
    } catch (_) {
      return;
    }
    total++;
    var bestMiss = 1 << 30, bestBagMiss = 1 << 30;
    var bestRho = kIdentityName;
    for (final rho0 in group) {
      final pred = predictStream(alg, rho0);
      final miss = _compareWindows(rows, pred);
      final bag = _compareBag(rows, pred);
      if (miss < bestMiss || (miss == bestMiss && bag < bestBagMiss)) {
        bestMiss = miss;
        bestRho = rho0.join(',');
      }
      if (bag < bestBagMiss) bestBagMiss = bag;
    }
    final rotated = bestRho == kIdentityName ? '' : '  (rotated holding orientation)';
    knownOrientation[key] = bestRho.split(',').map(int.parse).toList();
    if (bestMiss == 0) {
      clean++;
      orientations[bestRho] = (orientations[bestRho] ?? 0) + 1;
      print('  ${label.padRight(30)} take ${rows.first.take}  ✓ matches$rotated');
    } else if (bestBagMiss == 0) {
      // Right turns, grouped differently in time — e.g. an M2 executed as two
      // separate M turns. Correct execution, just not one motion.
      clean++;
      regrouped++;
      print('  ${label.padRight(30)} take ${rows.first.take}  ✓ matches — but '
          'split across motions (e.g. a double done as two quarter turns)');
    } else {
      print('  ${label.padRight(30)} take ${rows.first.take}  ✗ $bestBagMiss/'
          '${rows.length} turns differ from the label — genuine mis-execution');
    }
  });
  final phrased = regrouped > 0
      ? '  ($regrouped of them with a double split into two quarter turns)'
      : '';
  print('  => $clean/$total takes execute their label correctly$phrased');
  if (orientations.length > 1) {
    print('  => ${orientations.length} DIFFERENT holding orientations across takes '
        '— the cube was reoriented between takes, so a reconstruction cannot '
        'assume it starts aligned.');
  }
}

const kIdentityName = '0,1,2,3,4,5';

/// Per-take starting orientation, resolved by the execution check against the
/// ground-truth label. Stands in for the app's §13 orientation setting.
final knownOrientation = <String, List<int>>{};

/// The label with its take suffix removed.
String _algOf(String key) => key.substring(0, key.lastIndexOf('#'));

String _canon(List<Move> alg) => algToString(canonicalCollapsed(alg));

/// The central diagnostic: the distribution of inter-move gaps. Gaps are taken
/// WITHIN a take only — the pause between two takes is not a solving gap.
void _gapHistogram(Map<String, List<Row>> byTake) {
  final gaps = <int>[];
  for (final rows in byTake.values) {
    for (var i = 1; i < rows.length; i++) {
      final d = rows[i].cubeMs - rows[i - 1].cubeMs;
      if (d >= 0 && d < 2000) gaps.add(d);
    }
  }
  if (gaps.isEmpty) return print('no usable gaps');
  gaps.sort();

  print('-- inter-move gap distribution (cube clock, ms) --');
  const buckets = [0, 5, 10, 20, 30, 40, 55, 70, 90, 120, 160, 220, 300, 500, 1000];
  for (var i = 0; i < buckets.length - 1; i++) {
    final lo = buckets[i], hi = buckets[i + 1];
    final n = gaps.where((g) => g >= lo && g < hi).length;
    if (n == 0 && i > 0 && i < buckets.length - 2) {
      print('  ${'$lo-$hi'.padLeft(9)}  .');
      continue;
    }
    final bar = '#' * (40 * n ~/ max(gaps.length, 1)).clamp(0, 40);
    print('  ${'$lo-$hi'.padLeft(9)}  ${n.toString().padLeft(4)} $bar');
  }
  int pct(int p) => gaps[(gaps.length * p ~/ 100).clamp(0, gaps.length - 1)];
  print('  p05 ${pct(5)}  p25 ${pct(25)}  median ${pct(50)}  p75 ${pct(75)}  p95 ${pct(95)}');

  // Find the emptiest gap band between 10 and 120 ms — the natural threshold.
  var bestThr = 60, bestCount = 1 << 30;
  // Search only 30-100ms: below that is within-motion spread, above is a real
  // pause, and a local empty band at 25ms is not a motion boundary.
  for (var t = 30; t <= 100; t += 5) {
    final n = gaps.where((g) => g >= t - 10 && g < t + 10).length;
    if (n < bestCount) {
      bestCount = n;
      bestThr = t;
    }
  }
  final ambiguous = gaps.where((g) => g >= bestThr - 15 && g < bestThr + 15).length;
  print('  suggested segmentation threshold: ${bestThr}ms '
      '(${(100 * ambiguous / gaps.length).toStringAsFixed(1)}% of gaps land within '
      '+/-15ms of it)');
  print(ambiguous / gaps.length < 0.05
      ? '  => CLEAN separation: motion segmentation is safe on this cube.'
      : '  => SMEARED: the timing gate is unreliable here; expect the eval numbers '
          'to be optimistic.');
}

/// Did we capture every quarter turn the alg should have produced?
void _completeness(Map<String, List<Row>> byTake) {
  print('-- capture completeness (observed vs expected quarter turns) --');
  var checked = 0;
  byTake.forEach((key, rows) {
    final label = _algOf(key);
    if (label.isEmpty) return;
    List<Move> alg;
    try {
      alg = parseAlg(label);
    } catch (_) {
      print('  ${label.padRight(34)} (unparseable label)');
      return;
    }
    var expected = 0;
    for (final m in alg) {
      for (final s in decompose(m).sensed) {
        expected += s.amount == 2 ? 2 : 1;
      }
    }
    checked++;
    final ok = expected == rows.length;
    print('  ${label.padRight(34)} expected $expected, got ${rows.length}'
        '${ok ? "  ok" : "  <-- MISMATCH (dropped or extra events)"}');
  });
  if (checked == 0) print('  (no parseable labels — capture with ground truth to use this)');
}

/// Run the reconstruction on the real stream and compare to the label.
void _reconstruct(Map<String, List<Row>> byTake) {
  print('-- reconstruction against ground truth --');
  var n = 0, ok = 0;
  byTake.forEach((key, rows) {
    final label = _algOf(key);
    if (label.isEmpty) return;
    List<Move> truth;
    try {
      truth = parseAlg(label);
    } catch (_) {
      return;
    }
    final stream = [
      for (final r in rows) Reported(r.face, r.prime, r.cubeMs)
    ];
    final st = Stats.fit(allAlgs().where((a) => a != label).toList());
    // ★ The starting frame is SUPPLIED, not inferred. Inferring it from the
    // move stream is not identifiable: the parse is only determined up to a
    // rotation, and the face-frequency prior simply prefers whichever rotation
    // lands the moves on R and U. In the trainer this comes from the §13
    // orientation setting; here it comes from the execution check.
    final res = methodBv2(stream, st, const BWeights(allowWide: false),
        initial: knownOrientation[key] ?? identity);
    n++;
    final got = _canon(res.best);
    final want = _canon(truth);
    if (got == want) {
      ok++;
    } else {
      print('  MISS  want $want');
      print('        got  $got   (margin ${res.margin.toStringAsFixed(2)})');
    }
  });
  if (n == 0) return print('  (no labelled algs)');
  print('  ${(100 * ok / n).toStringAsFixed(1)}% exact ($ok/$n)');
}
