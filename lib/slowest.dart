// "Practice the slowest" selection logic, kept pure so it can be unit-tested
// without a database. A case's "slowness" is the average of its most recent
// few recorded solves (see [computeRecentAverages]); the user then drills either
// the N slowest or every case above a time threshold.

enum SlowestMode { topN, threshold }

// What makes a case "weak": how slow it is, or how often it goes wrong.
enum WeaknessSource { slowestTime, mostFailed }

// A case ranked by how many times it has been botched.
class FailedAlg {
  final String alg;
  final int errorCount;

  const FailedAlg(this.alg, this.errorCount);
}

// The alg names to drill from a ranked (most-failed-first) pool: the [topN]
// most-failed, or every case with at least [minErrors] errors.
List<String> selectMostFailed(
  List<FailedAlg> mostFailedFirst, {
  required SlowestMode mode,
  required int topN,
  required int minErrors,
}) {
  final Iterable<FailedAlg> chosen = mode == SlowestMode.topN
      ? mostFailedFirst.take(topN)
      : mostFailedFirst.where((f) => f.errorCount >= minErrors);
  return [for (final f in chosen) f.alg];
}

// A case ranked by its recent average solve time.
class SlowestAlg {
  final String alg;
  final double recentAvgMs;
  final int sampleCount; // how many recent solves the average is over (≤ window)

  const SlowestAlg(this.alg, this.recentAvgMs, this.sampleCount);
}

// Averages each alg's most recent [window] solves. [rowsNewestFirst] must list
// solves newest-first (globally is enough — we only cap per alg), each as
// (alg, resultMs). Result is sorted slowest average first. Algs with fewer than
// [window] solves are averaged over whatever they have (down to a single time).
List<SlowestAlg> computeRecentAverages(
    List<({String alg, int resultMs})> rowsNewestFirst, int window) {
  final Map<String, List<int>> recent = {};
  for (final row in rowsNewestFirst) {
    final list = recent.putIfAbsent(row.alg, () => <int>[]);
    if (list.length < window) list.add(row.resultMs);
  }
  final result = <SlowestAlg>[
    for (final e in recent.entries)
      SlowestAlg(
          e.key, e.value.reduce((a, b) => a + b) / e.value.length, e.value.length),
  ];
  result.sort((a, b) => b.recentAvgMs.compareTo(a.recentAvgMs));
  return result;
}

// The alg names to drill, given a ranked (slowest-first) pool and the user's
// choice: the [topN] slowest, or every case whose recent average is at or above
// [thresholdMs]. Top-N clamps to the pool size.
List<String> selectSlowest(
  List<SlowestAlg> slowestFirst, {
  required SlowestMode mode,
  required int topN,
  required double thresholdMs,
}) {
  final Iterable<SlowestAlg> chosen = mode == SlowestMode.topN
      ? slowestFirst.take(topN)
      : slowestFirst.where((s) => s.recentAvgMs >= thresholdMs);
  return [for (final s in chosen) s.alg];
}
