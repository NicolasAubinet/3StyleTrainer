import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/equalizing_selector.dart';

List<String> pool(int n) => [for (int i = 0; i < n; i++) 'c$i'];

List<String> draw(EqualizingSelector sel, int k) =>
    [for (int i = 0; i < k; i++) sel.getNextAlg()!.name];

// Draw k, recording each solve as the app does during a recording run.
Map<String, int> playRecording(EqualizingSelector sel, List<String> algs, int k) {
  for (int i = 0; i < k; i++) {
    sel.recordSolve(sel.getNextAlg()!.name);
  }
  return {for (final a in algs) a: sel.countOf(a)};
}

int range(Iterable<int> xs) => xs.reduce(max) - xs.reduce(min);

void main() {
  group('EqualizingSelector', () {
    test('empty pool returns null', () {
      expect(EqualizingSelector(algs: []).getNextAlg(), isNull);
    });

    test('recordSolve increments the count', () {
      final sel = EqualizingSelector(algs: pool(10), counts: {'c0': 3});
      expect(sel.countOf('c0'), 3);
      sel.recordSolve('c0');
      expect(sel.countOf('c0'), 4);
      sel.recordSolve('c1');
      expect(sel.countOf('c1'), 1);
    });

    test('a skipped case never reappears this session', () {
      final sel = EqualizingSelector(algs: pool(20), random: Random(3));
      sel.skip('c7');
      for (final a in draw(sel, 5000)) {
        expect(a, isNot('c7'));
      }
    });

    test('getNextAlg returns null once every case is skipped', () {
      final sel = EqualizingSelector(algs: pool(3));
      sel..skip('c0')..skip('c1')..skip('c2');
      expect(sel.getNextAlg(), isNull);
    });

    test('never shows the same case twice in a row', () {
      final counts = {for (final a in pool(30)) a: 5};
      counts['c0'] = 0; // a laggard, to exercise sit-out passes
      final sel =
          EqualizingSelector(algs: pool(30), counts: counts, random: Random(1));
      final seq = draw(sel, 5000);
      for (int i = 1; i < seq.length; i++) {
        expect(seq[i], isNot(seq[i - 1]), reason: 'back-to-back at $i');
      }
    });

    // The core guarantee: within a pass every case is served at most once. With
    // level counts each pass is a full pass, so every block of N is a permutation.
    test('each pass is a permutation when counts are level (no repeat per pass)',
        () {
      final algs = pool(21);
      final counts = {for (final a in algs) a: 4};
      final sel =
          EqualizingSelector(algs: algs, counts: counts, random: Random(2));
      final seq = draw(sel, 21 * 200);
      for (int start = 0; start < seq.length; start += 21) {
        final block = seq.sublist(start, start + 21).toSet();
        expect(block.length, 21, reason: 'a case repeated within a pass');
      }
    });

    // The whole point: recording every solve keeps counts even.
    test('keeps recorded counts even (level start stays level)', () {
      final algs = pool(21);
      final sel = EqualizingSelector(algs: algs, random: Random(5));
      final counts = playRecording(sel, algs, 50 * 21);
      expect(range(counts.values), lessThanOrEqualTo(1));
    });

    // Recording off freezes counts -> plain even cycle even when counts are skewed.
    test('selects evenly when recording is off, ignoring counts', () {
      final algs = pool(30);
      final counts = {for (final a in algs) a: 0};
      counts['c0'] = 500; // a skew healing would react to, but recording is off
      final sel = EqualizingSelector(
          algs: algs, counts: counts, recording: false, random: Random(3));
      final freq = {for (final a in algs) a: 0};
      for (final a in draw(sel, 30 * 400)) {
        freq[a] = freq[a]! + 1;
      }
      expect(range(freq.values), lessThanOrEqualTo(1));
    });

    // A behind case is favored (shown more) but never over-shown: at most once
    // per pass, and well spaced.
    test('favors a lagging case but shows it at most once per pass', () {
      final algs = pool(60);
      final counts = {for (final a in algs) a: 30};
      counts['c0'] = 0; // far behind; counts stay fixed (no recording here)
      final sel =
          EqualizingSelector(algs: algs, counts: counts, random: Random(4));
      final seq = draw(sel, 60 * 200);

      final laggard = seq.where((a) => a == 'c0').length;
      final otherAvg = (seq.length - laggard) / (algs.length - 1);
      expect(laggard, greaterThan(otherAvg), reason: 'laggard should be favored');

      // Gaps between its appearances stay large -> never shown too often.
      int? last;
      var minGap = 1 << 30;
      for (int i = 0; i < seq.length; i++) {
        if (seq[i] == 'c0') {
          if (last != null) minGap = min(minGap, i - last);
          last = i;
        }
      }
      expect(minGap, greaterThan(10),
          reason: 'laggard reappeared too soon (min gap $minGap)');
    });

    // Drift healing: a case whose times were all deleted catches back up.
    test('a wiped case catches back up when recording', () {
      final algs = pool(21);
      final counts = {for (final a in algs) a: 30};
      counts['c0'] = 0;
      final sel =
          EqualizingSelector(algs: algs, counts: counts, random: Random(6));
      final finalCounts = playRecording(sel, algs, 21 * 200);
      final others = [
        for (final a in algs)
          if (a != 'c0') finalCounts[a]!
      ];
      final otherAvg = others.reduce((x, y) => x + y) / others.length;
      expect(finalCounts['c0']!, greaterThan(otherAvg - 6),
          reason: 'wiped case should have closed the gap');
    });

    test('requeue lets a served case reappear later this session', () {
      final sel = EqualizingSelector(algs: pool(20), random: Random(7));
      final first = sel.getNextAlg()!.name;
      sel.requeue(first);
      final rest = draw(sel, 60);
      expect(rest, contains(first));
    });
  });
}
