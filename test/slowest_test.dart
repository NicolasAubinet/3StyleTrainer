import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/slowest.dart';

void main() {
  group('computeRecentAverages', () {
    test('averages only the most recent `window` solves per alg', () {
      // Newest-first: AB most recent solves are 1000, 2000, 3000 (older 9000
      // ignored with window=3). BA has 4000, 6000.
      final rows = <({String alg, int resultMs})>[
        (alg: 'AB', resultMs: 1000),
        (alg: 'AB', resultMs: 2000),
        (alg: 'BA', resultMs: 4000),
        (alg: 'AB', resultMs: 3000),
        (alg: 'AB', resultMs: 9000),
        (alg: 'BA', resultMs: 6000),
      ];

      final result = computeRecentAverages(rows, 3);

      // BA avg 5000 > AB avg 2000 → BA first.
      expect(result.map((s) => s.alg).toList(), ['BA', 'AB']);
      expect(result[0].recentAvgMs, 5000);
      expect(result[0].sampleCount, 2);
      expect(result[1].recentAvgMs, 2000);
      expect(result[1].sampleCount, 3);
    });

    test('takes the first `window` rows in list order, not the smallest/largest',
        () {
      // The feature depends on the DB feeding rows newest-first: whichever rows
      // come *first* are the ones averaged. Reversing the input must change the
      // result even though the multiset of times is identical.
      final newestFirst = <({String alg, int resultMs})>[
        (alg: 'AB', resultMs: 1000),
        (alg: 'AB', resultMs: 1000),
        (alg: 'AB', resultMs: 4000),
      ];
      final reversed = newestFirst.reversed.toList();

      expect(computeRecentAverages(newestFirst, 2).single.recentAvgMs, 1000);
      expect(computeRecentAverages(reversed, 2).single.recentAvgMs, 2500);
    });

    test('window of 1 keeps only the most recent solve', () {
      final rows = <({String alg, int resultMs})>[
        (alg: 'AB', resultMs: 1200),
        (alg: 'AB', resultMs: 9999),
      ];

      final result = computeRecentAverages(rows, 1);

      expect(result.single.recentAvgMs, 1200);
      expect(result.single.sampleCount, 1);
    });

    test('averages over fewer solves when under the window', () {
      final rows = <({String alg, int resultMs})>[
        (alg: 'AB', resultMs: 1500),
      ];

      final result = computeRecentAverages(rows, 3);

      expect(result.single.recentAvgMs, 1500);
      expect(result.single.sampleCount, 1);
    });

    test('produces a fractional average (no integer truncation)', () {
      final rows = <({String alg, int resultMs})>[
        (alg: 'AB', resultMs: 1000),
        (alg: 'AB', resultMs: 1000),
        (alg: 'AB', resultMs: 1001),
      ];

      final result = computeRecentAverages(rows, 3);

      expect(result.single.recentAvgMs, closeTo(1000.333, 0.001));
    });

    test('caps each alg independently regardless of interleaving', () {
      final rows = <({String alg, int resultMs})>[
        (alg: 'AB', resultMs: 1000),
        (alg: 'BA', resultMs: 2000),
        (alg: 'AB', resultMs: 1000),
        (alg: 'BA', resultMs: 2000),
        (alg: 'AB', resultMs: 1000), // AB's 3rd — dropped at window=2
        (alg: 'BA', resultMs: 8000), // BA's 3rd — dropped at window=2
      ];

      final result = computeRecentAverages(rows, 2);

      final byAlg = {for (final s in result) s.alg: s};
      expect(byAlg['AB']!.sampleCount, 2);
      expect(byAlg['AB']!.recentAvgMs, 1000);
      expect(byAlg['BA']!.sampleCount, 2);
      expect(byAlg['BA']!.recentAvgMs, 2000);
    });

    test('empty input yields no rows', () {
      expect(computeRecentAverages([], 3), isEmpty);
    });
  });

  group('selectSlowest', () {
    final ranked = [
      const SlowestAlg('A', 5000, 3),
      const SlowestAlg('B', 3000, 3),
      const SlowestAlg('C', 1000, 2),
    ];

    test('top-N takes the N slowest and clamps to pool size', () {
      expect(
          selectSlowest(ranked, mode: SlowestMode.topN, topN: 2, thresholdMs: 0),
          ['A', 'B']);
      expect(
          selectSlowest(ranked, mode: SlowestMode.topN, topN: 99, thresholdMs: 0),
          ['A', 'B', 'C']);
    });

    test('top-N of 0 selects nothing', () {
      expect(
          selectSlowest(ranked, mode: SlowestMode.topN, topN: 0, thresholdMs: 0),
          isEmpty);
    });

    test('threshold keeps cases at or above the cutoff (inclusive)', () {
      expect(
          selectSlowest(ranked,
              mode: SlowestMode.threshold, topN: 0, thresholdMs: 3000),
          ['A', 'B']); // B == 3000 is included
      expect(
          selectSlowest(ranked,
              mode: SlowestMode.threshold, topN: 0, thresholdMs: 6000),
          isEmpty);
    });

    test('empty pool selects nothing in either mode', () {
      expect(
          selectSlowest(const [],
              mode: SlowestMode.topN, topN: 5, thresholdMs: 0),
          isEmpty);
      expect(
          selectSlowest(const [],
              mode: SlowestMode.threshold, topN: 0, thresholdMs: 1000),
          isEmpty);
    });
  });

  group('rank then select (end-to-end)', () {
    final rows = <({String alg, int resultMs})>[
      // AB recent avg 1000, BA recent avg 5000, CD recent avg 3000.
      (alg: 'BA', resultMs: 5000),
      (alg: 'CD', resultMs: 3000),
      (alg: 'AB', resultMs: 1000),
      (alg: 'BA', resultMs: 5000),
      (alg: 'CD', resultMs: 3000),
      (alg: 'AB', resultMs: 1000),
    ];

    test('top-N drills the slowest cases by recent average', () {
      final ranked = computeRecentAverages(rows, 3);
      expect(
          selectSlowest(ranked,
              mode: SlowestMode.topN, topN: 2, thresholdMs: 0),
          ['BA', 'CD']);
    });

    test('threshold drills every case at or above the cutoff', () {
      final ranked = computeRecentAverages(rows, 3);
      expect(
          selectSlowest(ranked,
              mode: SlowestMode.threshold, topN: 0, thresholdMs: 3000),
          ['BA', 'CD']);
    });
  });
}
