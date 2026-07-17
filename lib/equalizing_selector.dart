import 'dart:math';

import 'alg_provider.dart';
import 'alg_structs.dart';

/// Time-race case selector that keeps recorded-time counts close to even.
///
/// **Base: a without-replacement cycle.** Each *pass* serves every eligible case
/// at most once, so when counts are level everyone is served once per pass and
/// they stay even — a case never recurs until the pool has cycled. This is the
/// hard "no case is shown more than once per pass/session" guarantee.
///
/// **Healing: over-represented cases sit out.** When a case is *behind* the pack
/// (times deleted, added mid-life, or a run recorded while others didn't), the
/// cases that are *ahead* of the current minimum sit out a pass with a bounded
/// probability, so the laggard closes the gap over several sessions — while still
/// being shown only once per pass. The most-behind case is served last in its
/// pass, maximising the spacing between its once-per-pass appearances.
///
/// Healing is active only while [recording]; with it off, counts are frozen and
/// every pass is a plain shuffled cycle. The mechanism is invisible to the user.
class EqualizingSelector implements AlgProvider {
  /// Max probability that a single ahead-of-the-pack case sits out a pass.
  /// Higher = laggards heal faster but show up a bit more often meanwhile.
  static const double MAX_SITOUT_PROB = 0.5;

  /// How fast the sit-out probability ramps with a case's surplus over the
  /// current minimum (surplus of `MAX_SITOUT_PROB / SITOUT_RAMP` saturates it).
  static const double SITOUT_RAMP = 0.15;

  final List<String> _algs;
  final Map<String, int> _counts;
  final Random _random;

  /// When false (recording off / show-next-alg prefetch), counts are frozen and
  /// each pass is a plain shuffled cycle (no sit-out healing).
  bool recording;

  final _bag = <String>[]; // cases left to serve in the current pass
  final _skipped = <String>{}; // cases dropped for the rest of the session
  String? _lastServed;

  EqualizingSelector({
    required List<String> algs,
    Map<String, int> counts = const {},
    this.recording = true,
    Random? random,
  })  : _algs = List.of(algs),
        _counts = {for (final a in algs) a: counts[a] ?? 0},
        _random = random ?? Random();

  int countOf(String alg) => _counts[alg] ?? 0;

  @override
  Alg? getNextAlg() {
    if (_algs.isEmpty) return null;
    if (_bag.isEmpty) _refillPass();
    if (_bag.isEmpty) return null; // every case skipped
    final chosen = _bag.removeAt(0);
    _lastServed = chosen;
    return Alg(chosen);
  }

  /// Build the next pass: every eligible case once, minus ahead-of-the-pack
  /// cases that sit this pass out (healing). Order is shuffled, the most-behind
  /// case is served last, and the first case never repeats the last one served.
  void _refillPass() {
    final pool = [
      for (final a in _algs)
        if (!_skipped.contains(a)) a,
    ];
    if (pool.isEmpty) return;

    int minCount = 1 << 30;
    for (final a in pool) {
      final c = _counts[a] ?? 0;
      if (c < minCount) minCount = c;
    }

    final pass = <String>[];
    for (final a in pool) {
      if (!recording) {
        pass.add(a);
        continue;
      }
      final surplus = (_counts[a] ?? 0) - minCount;
      final sitOut = min(MAX_SITOUT_PROB, SITOUT_RAMP * surplus);
      if (surplus <= 0 || _random.nextDouble() >= sitOut) {
        pass.add(a); // laggards (surplus 0) are always in
      }
    }

    pass.shuffle(_random);
    if (pass.length > 1) {
      // Serve the most-behind case last, so its once-per-pass appearances are
      // maximally spaced.
      final li = pass.indexWhere((a) => (_counts[a] ?? 0) == minCount);
      if (li >= 0 && li != pass.length - 1) {
        pass.add(pass.removeAt(li));
      }
      // No back-to-back across the pass boundary.
      if (pass.first == _lastServed) {
        final j = 1 + _random.nextInt(pass.length - 1);
        final t = pass[0];
        pass[0] = pass[j];
        pass[j] = t;
      }
    }
    _bag
      ..clear()
      ..addAll(pass);
  }

  /// Record a solve mid-session so healing stays fresh across a long "again"
  /// chain without re-querying the DB.
  void recordSolve(String alg) {
    _counts[alg] = (_counts[alg] ?? 0) + 1;
  }

  /// The selector is session-continuous: counts and the current pass carry
  /// across an "again", so reset is a no-op.
  @override
  void reset({List<String> skippedAlgs = const []}) {}

  /// Time race shows a time-based progress bar, not a provider one.
  @override
  double getProgression({int preFetchedAlgsCount = 0}) => 0;

  /// Put an already-served case back so it reappears later this pass — but not
  /// as the immediate next case (the caller draws the next one first).
  @override
  void requeue(String algName) {
    _skipped.remove(algName);
    if (_bag.contains(algName) || _bag.length < 2) return;
    _bag.insert(1 + _random.nextInt(_bag.length), algName);
  }

  /// Drop a case for the rest of the session.
  @override
  void skip(String algName) {
    _skipped.add(algName);
    _bag.remove(algName);
  }

  @override
  int get totalAlgs => _algs.length;
}
