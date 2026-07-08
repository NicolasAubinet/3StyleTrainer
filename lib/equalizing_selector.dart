import 'dart:math';

import 'alg_provider.dart';
import 'alg_structs.dart';

/// Time-race case selector that keeps recorded-time counts converging toward
/// even. Weighted sampling *with replacement* over the full valid-case pool,
/// behind a recency cooldown:
///
/// - **Cooldown (hard spacing):** the last [cooldownWindow] shown cases are
///   ineligible, guaranteeing no back-to-back and no repeat within the window.
///   Session-scoped and in-memory — not persisted across sessions.
/// - **Weighting (soft balance):** among eligible cases, pick weighted-random
///   by a gentle function of the record deficit. Only active while [recording];
///   when off, counts are frozen so selection is uniform among eligible cases.
///
/// The mechanism is invisible to the user; time race has no cycle/pass notion.
class EqualizingSelector implements AlgProvider {
  static const double NUDGE = 0.05;
  static const int DEFICIT_CAP = 20;
  static const int COOLDOWN_TARGET = 100;

  final List<String> _algs;
  final Map<String, int> _counts;
  final Random _random;

  /// When false (recording off / show-next-alg prefetch), counts are frozen
  /// and selection is uniform among eligible cases.
  bool recording;

  final int _cooldownWindow;
  final _cooldownQueue = <String>[]; // FIFO of recently shown cases
  final _inCooldown = <String>{}; // membership mirror of the queue

  EqualizingSelector({
    required List<String> algs,
    Map<String, int> counts = const {},
    this.recording = true,
    Random? random,
  })  : _algs = List.of(algs),
        _counts = {for (final a in algs) a: counts[a] ?? 0},
        _random = random ?? Random(),
        _cooldownWindow = _computeWindow(algs.length);

  /// Cases that must stay pickable, so weighting stays meaningful in small
  /// pools: `max(8, 25% of pool)`.
  static int _minEligible(int poolSize) => max(8, (poolSize * 0.25).floor());

  /// `W = min(COOLDOWN_TARGET, poolSize - MIN_ELIGIBLE)`, floored at 0. Always
  /// leaves at least one eligible case.
  static int _computeWindow(int poolSize) =>
      max(0, min(COOLDOWN_TARGET, poolSize - _minEligible(poolSize)));

  int get cooldownWindow => _cooldownWindow;

  int countOf(String alg) => _counts[alg] ?? 0;

  @override
  Alg? getNextAlg() {
    if (_algs.isEmpty) {
      return null;
    }

    var eligible = [
      for (final a in _algs)
        if (!_inCooldown.contains(a)) a,
    ];
    if (eligible.isEmpty) {
      // Only reachable in degenerate tiny pools; ignore the cooldown.
      eligible = _algs;
    }

    final chosen =
        recording ? _pickWeighted(eligible) : _pickUniform(eligible);

    _cooldownQueue.add(chosen);
    _inCooldown.add(chosen);
    if (_cooldownQueue.length > _cooldownWindow) {
      _inCooldown.remove(_cooldownQueue.removeAt(0));
    }
    return Alg(chosen);
  }

  String _pickUniform(List<String> eligible) =>
      eligible[_random.nextInt(eligible.length)];

  String _pickWeighted(List<String> eligible) {
    int ref = 0;
    for (final c in _counts.values) {
      if (c > ref) ref = c;
    }

    final weights = <double>[];
    double total = 0;
    for (final a in eligible) {
      final deficit = (ref - (_counts[a] ?? 0)).clamp(0, DEFICIT_CAP);
      final weight = 1 + NUDGE * deficit;
      weights.add(weight);
      total += weight;
    }

    double r = _random.nextDouble() * total;
    for (int i = 0; i < eligible.length; i++) {
      r -= weights[i];
      if (r < 0) {
        return eligible[i];
      }
    }
    return eligible.last; // floating-point rounding guard
  }

  /// Record a solve mid-session so weights stay fresh across a long "again"
  /// chain without re-querying the DB.
  void recordSolve(String alg) {
    _counts[alg] = (_counts[alg] ?? 0) + 1;
  }

  /// The selector is session-continuous: counts and cooldown carry across an
  /// "again", so reset is a no-op (there is no skip/without-replacement pool).
  @override
  void reset({List<String> skippedAlgs = const []}) {}

  /// Time race shows a time-based progress bar, not a provider one.
  @override
  double getProgression({int preFetchedAlgsCount = 0}) => 0;

  @override
  int get totalAlgs => _algs.length;
}
