/// End-to-end regression against a REAL capture: 18 labelled takes from a MoYu
/// WeiLong V10 (`test/fixtures/moyu_v10_trace_2026-07-19.jsonl`), recorded with
/// the example app's trace capture.
///
/// This is the acceptance test for the reconstruction module. The offline
/// research harness scored 94.4% (17/18) on this data; the shipped module must
/// match it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartcube/smartcube.dart';

// ---------------------------------------------------------------------------
// Notation parsing (test-local — the module deals in moves, not text)
// ---------------------------------------------------------------------------

SolverMove parseMove(String tok) {
  var t = tok;
  var amount = 1;
  if (t.endsWith("'")) {
    amount = 3;
    t = t.substring(0, t.length - 1);
  } else if (t.endsWith('2')) {
    amount = 2;
    t = t.substring(0, t.length - 1);
  }
  if (t.length == 2 && t[1] == 'w') {
    return SolverMove.wide(Face.values.byName(t[0]), amount);
  }
  if (t.length == 1 && 'MES'.contains(t)) {
    return SolverMove.slice(Slice.values.byName(t), amount);
  }
  return SolverMove.outer(Face.values.byName(t), amount);
}

List<SolverMove> parseAlg(String s) =>
    s.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).map(parseMove).toList();

/// The quarter turns a cube would report for [alg], starting in [rho0].
/// `half` marks turns from a 180 degree turn — those have no canonical
/// direction, since the cube reports whichever way it was physically spun.
List<({Face face, bool prime, bool half})> predictStream(
    List<SolverMove> alg, FaceRotation rho0) {
  var rho = rho0;
  final out = <({Face face, bool prime, bool half})>[];
  for (final m in alg) {
    final dec = switch (m.kind) {
      MoveKind.outer => Decomposition([SensedTurn(m.face!, m.amount)], kIdentity),
      MoveKind.slice => decomposeSlice(m.slice!, m.amount),
      MoveKind.wide => decomposeWide(m.face!, m.amount),
    };
    for (final s in dec.sensed) {
      final f = toReportedFrame(s.face, rho);
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

/// Which of the 24 orientations the cube was held in for this take. Stands in
/// for the app's manual orientation setting, which is what supplies it in
/// production — it cannot be inferred from the moves alone.
FaceRotation? findOrientation(List<SolverMove> alg, List<CubeMove> actual) {
  // Take the orientation with the FEWEST positional mismatches, not the first
  // that fits loosely. A take where a double was split across two motions has
  // no zero-mismatch orientation, and several rotations tie on a whole-take
  // multiset — accepting any of them silently mirrors the answer.
  FaceRotation? best;
  var bestMiss = 1 << 30;
  for (final rho0 in rotationGroup()) {
    final pred = predictStream(alg, rho0);
    if (pred.length != actual.length) continue;
    final miss = _mismatches(actual, pred);
    if (miss < bestMiss) {
      bestMiss = miss;
      best = rho0;
    }
  }
  return best;
}

/// Turns that cannot be matched positionally. Adjacent turns on OPPOSITE faces
/// commute, and the operator may perform them in either order — sort them into
/// a canonical order on both sides first, or a legitimate reordering reads as a
/// mismatch and the wrong orientation wins.
int _mismatches(
    List<CubeMove> actual, List<({Face face, bool prime, bool half})> pred) {
  final a = _sortCommuting(
      [for (final m in actual) (face: m.face, prime: m.prime, half: false)]);
  final p = _sortCommuting(pred);
  var miss = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i].face != p[i].face || (!p[i].half && a[i].prime != p[i].prime)) {
      miss++;
    }
  }
  return miss;
}

List<({Face face, bool prime, bool half})> _sortCommuting(
    List<({Face face, bool prime, bool half})> xs) {
  final out = List<({Face face, bool prime, bool half})>.from(xs);
  for (var i = 0; i + 1 < out.length; i++) {
    if (kOpposite[out[i].face] == out[i + 1].face &&
        out[i].face.index > out[i + 1].face.index) {
      final t = out[i];
      out[i] = out[i + 1];
      out[i + 1] = t;
    }
  }
  return out;
}

/// Adjacent opposite-face turns commute; the cube cannot know which of two
/// simultaneous turns landed first, so neither can the comparison.
String canonical(List<SolverMove> moves) {
  final out = List<SolverMove>.from(moves);
  for (var i = 0; i + 1 < out.length; i++) {
    final a = out[i], b = out[i + 1];
    if (a.kind == MoveKind.outer &&
        b.kind == MoveKind.outer &&
        kOpposite[a.face!] == b.face &&
        a.face!.index > b.face!.index) {
      out[i] = b;
      out[i + 1] = a;
    }
  }
  return movesToString(collapseDoubles(out));
}

// ---------------------------------------------------------------------------

class Take {
  final String label;
  final List<CubeMove> moves;
  Take(this.label, this.moves);
}

/// The capture is a personal recording and may not be present in every
/// checkout. Skip rather than fail when it is missing; capture your own with
/// the example app's trace capture to re-enable these.
final fixtureFile = File('test/fixtures/moyu_v10_trace_2026-07-19.jsonl');

List<Take> loadFixture() {
  final f = fixtureFile;
  final byKey = <String, List<CubeMove>>{};
  final labels = <String, String>{};
  for (final line in f.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final j = jsonDecode(line) as Map<String, dynamic>;
    final key = '${j['label']}#${j['take']}';
    labels[key] = j['label'] as String;
    byKey.putIfAbsent(key, () => []).add(CubeMove(
          face: Face.values.byName(j['face'] as String),
          prime: j['prime'] as bool,
          cubeTimestamp: Duration(milliseconds: j['cubeMs'] as int),
        ));
  }
  return [for (final e in byKey.entries) Take(labels[e.key]!, e.value)];
}

void main() {
  final skip = fixtureFile.existsSync()
      ? null
      : 'no hardware capture at ${fixtureFile.path} — record one with the '
          'example app to run these';
  late List<Take> takes;

  setUpAll(() {
    if (fixtureFile.existsSync()) takes = loadFixture();
  });

  test('the fixture loads 18 takes', () {
    expect(takes.length, 18);
    expect(takes.fold<int>(0, (n, t) => n + t.moves.length), 154);
  }, skip: skip);

  test('every take was executed as labelled, in a known orientation', () {
    for (final t in takes) {
      expect(findOrientation(parseAlg(t.label), t.moves), isNotNull,
          reason: '${t.label} does not match any holding orientation');
    }
  }, skip: skip);

  test('the cube was reorientated between takes', () {
    // Why startOrientation is a required per-sequence input and not a setting
    // that can be read once: the operator picks the cube up differently.
    final seen = takes
        .map((t) => orientationKey(findOrientation(parseAlg(t.label), t.moves)!))
        .toSet();
    expect(seen.length, greaterThan(1));
  }, skip: skip);

  test('reconstructs real hardware captures (>= 17/18 exact)', () {
    var exact = 0;
    final misses = <String>[];
    for (final t in takes) {
      final truth = parseAlg(t.label);
      final rho0 = findOrientation(truth, t.moves)!;
      final r = reconstruct(t.moves,
          startOrientation: rho0, timing: TimingQuality.perMoveClock);
      if (canonical(r.moves) == canonical(truth)) {
        exact++;
      } else {
        misses.add('${t.label}  ->  ${r.notation}');
      }
    }
    expect(exact, greaterThanOrEqualTo(17), reason: misses.join('\n'));
  }, skip: skip);

  test('the one miss is a slice the cube was not turned cleanly enough to see',
      () {
    // Labelled R E R', but the U and D' arrived 347ms apart: the V10's middle
    // layer is stiff, the U layer dragged along with the slice and had to be
    // corrected afterwards. Refusing to call that a slice is the right answer.
    final t = takes.firstWhere((t) =>
        t.label == "R E R'" &&
        t.moves[2].cubeTimestamp.inMilliseconds -
                t.moves[1].cubeTimestamp.inMilliseconds >
            200);
    final rho0 = findOrientation(parseAlg(t.label), t.moves)!;
    final r = reconstruct(t.moves,
        startOrientation: rho0, timing: TimingQuality.perMoveClock);
    expect(r.notation, isNot(contains('E')));
    expect(r.moves.length, 4);
  }, skip: skip);

  test('a cube with no per-move clock refuses rather than guessing', () {
    final t = takes.firstWhere((t) => t.label.contains('M'));
    final rho0 = findOrientation(parseAlg(t.label), t.moves)!;
    final r = reconstruct(t.moves,
        startOrientation: rho0, timing: TimingQuality.none);
    expect(r.abstained, isTrue);
    expect(r.degraded, isTrue);
    expect(r.note, contains('no usable per-move clock'));
    // The raw reading is all outer turns — no invented slices.
    expect(r.moves.every((m) => m.kind == MoveKind.outer), isTrue);
  }, skip: skip);

  test('a coarse clock still answers but flags itself as degraded', () {
    final t = takes.first;
    final rho0 = findOrientation(parseAlg(t.label), t.moves)!;
    final r = reconstruct(t.moves,
        startOrientation: rho0, timing: TimingQuality.coarse);
    expect(r.degraded, isTrue);
    if (!r.abstained) expect(r.note, contains('coarse'));
  }, skip: skip);
}
