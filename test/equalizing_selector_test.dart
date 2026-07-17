import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/equalizing_selector.dart';

List<String> pool(int n) => [for (int i = 0; i < n; i++) 'c$i'];

Map<String, int> tally(EqualizingSelector sel, List<String> algs, int k) {
  final freq = {for (final a in algs) a: 0};
  for (int i = 0; i < k; i++) {
    final a = sel.getNextAlg()!.name;
    freq[a] = freq[a]! + 1;
  }
  return freq;
}

void main() {
  group('EqualizingSelector', () {
    test('empty pool returns null', () {
      expect(EqualizingSelector(algs: []).getNextAlg(), isNull);
    });

    test('cooldown window = min(100, pool - max(8, 25%))', () {
      expect(EqualizingSelector(algs: pool(50)).cooldownWindow, 38);
      expect(EqualizingSelector(algs: pool(21)).cooldownWindow, 13);
      expect(EqualizingSelector(algs: pool(400)).cooldownWindow, 100);
    });

    test('a skipped case never reappears this session', () {
      final sel = EqualizingSelector(algs: pool(20), random: Random(3));
      sel.skip('c7');
      for (int i = 0; i < 5000; i++) {
        expect(sel.getNextAlg()!.name, isNot('c7'));
      }
    });

    test('getNextAlg returns null once every case is skipped', () {
      final sel = EqualizingSelector(algs: pool(3));
      sel..skip('c0')..skip('c1')..skip('c2');
      expect(sel.getNextAlg(), isNull);
    });

    test('recordSolve increments the count', () {
      final sel = EqualizingSelector(algs: pool(10), counts: {'c0': 3});
      expect(sel.countOf('c0'), 3);
      sel.recordSolve('c0');
      expect(sel.countOf('c0'), 4);
      sel.recordSolve('c1');
      expect(sel.countOf('c1'), 1);
    });

    // Guarantee 1: no back-to-back, no repeat within the cooldown window.
    test('never repeats a case within the cooldown window', () {
      final sel = EqualizingSelector(algs: pool(50), random: Random(1));
      final w = sel.cooldownWindow;
      final history = <String>[];
      for (int i = 0; i < 5000; i++) {
        final a = sel.getNextAlg()!.name;
        final recent = history.length < w
            ? history
            : history.sublist(history.length - w);
        expect(recent.contains(a), isFalse,
            reason: 'case $a repeated within window $w');
        history.add(a);
      }
    });

    // Guarantee 2: equal counts -> statistically uniform selection.
    test('selects uniformly when counts are even (recording on)', () {
      final algs = pool(30);
      final counts = {for (final a in algs) a: 5};
      final sel =
          EqualizingSelector(algs: algs, counts: counts, random: Random(2));
      const k = 120000;
      final freq = tally(sel, algs, k);
      final expected = k / algs.length;
      for (final a in algs) {
        expect(freq[a]!, greaterThan(expected * 0.85));
        expect(freq[a]!, lessThan(expected * 1.15));
      }
    });

    // Recording off freezes counts -> uniform even when counts are skewed.
    test('selects uniformly when recording is off, ignoring counts', () {
      final algs = pool(30);
      final counts = {for (final a in algs) a: 0};
      counts['c0'] = 500; // heavy skew the weighting would react to
      final sel = EqualizingSelector(
          algs: algs, counts: counts, recording: false, random: Random(3));
      const k = 120000;
      final freq = tally(sel, algs, k);
      final expected = k / algs.length;
      for (final a in algs) {
        expect(freq[a]!, greaterThan(expected * 0.85));
        expect(freq[a]!, lessThan(expected * 1.15));
      }
    });

    // The soft nudge favors a laggard, but the cooldown keeps it bounded.
    test('favors a lagging case but stays bounded by the cooldown', () {
      final algs = pool(60);
      final counts = {for (final a in algs) a: 20};
      counts['c0'] = 0; // far-behind case
      final sel =
          EqualizingSelector(algs: algs, counts: counts, random: Random(4));
      const k = 120000;
      final freq = tally(sel, algs, k);

      final laggard = freq['c0']!;
      final otherAvg = (k - laggard) / (algs.length - 1);
      expect(laggard, greaterThan(otherAvg),
          reason: 'laggard should be favored over on-par cases');

      // At most one appearance per (W + 1) selections.
      final ceiling = k / (sel.cooldownWindow + 1);
      expect(laggard, lessThanOrEqualTo(ceiling.ceil() + 1));
    });
  });
}
