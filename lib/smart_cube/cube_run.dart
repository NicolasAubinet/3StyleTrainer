import '../alg_structs.dart';
import 'three_style_geometry.dart';

/// Where a cube-driven case is in its lifecycle.
enum CubePhase {
  /// No case in progress yet.
  idle,

  /// Pair shown, no move made yet — measuring recognition.
  recognition,

  /// First move made, working toward the expected state — measuring execution.
  execution,

  /// Case reached its expected state.
  complete,
}

/// The timing split of one completed case.
class CaseSplit {
  final Duration recognition;
  final Duration execution;

  /// Completed from a mid-case baseline, not the state the case was shown in:
  /// the alg was right, the cube wasn't.
  final bool recovered;

  const CaseSplit(this.recognition, this.execution, {this.recovered = false});

  Duration get total => recognition + execution;
}

/// Drives the cube-side of a case: splits it into recognition (pair shown →
/// first move) and execution (first move → expected state) and detects
/// completion. Pure Dart and UI-agnostic.
///
/// A case completes when the cube reaches the pair's expected end-state from
/// *any* baseline it has rested at — the case-start state plus any added via
/// [addBaseline] (a mid-alg pause, or a botch the user recovers from). Because
/// the check is full-state equality (parity aside — see [_matchIndex]), extra
/// baselines only ever catch a real execution, never fabricate one, and a wrong
/// alg can never auto-advance. A completion off any later baseline comes back
/// [CaseSplit.recovered].
/// Supports corner, edge, 2-flip, 2-twist and parity pairs ([supports]).
class CubeRunController {
  final AlgType algType;
  final DateTime Function() _now;

  CubeRunController(this.algType, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  CubePhase phase = CubePhase.idle;

  // Candidate baselines and their expected end-states (parallel lists), oldest
  // first. Index 0 is the case-start state and is never evicted.
  final List<String> _baselines = [];
  final List<String> _expecteds = [];
  // Bounds the candidate set against pathological flailing; index 0 is kept.
  static const int _maxBaselines = 12;

  String? _pair;
  String? _matched; // the state onState last completed on
  DateTime? _shownAt;
  DateTime? _firstMoveAt;
  Duration? _recognition;

  /// Whether cube-driven completion geometry exists for [type]. A supported type
  /// may still be unmappable at runtime (e.g. parity with non-adjacent buffers),
  /// which surfaces as a null expected state.
  static bool supports(AlgType type) =>
      type == AlgType.Corner ||
      type == AlgType.Edge ||
      type == AlgType.TwoFlip ||
      type == AlgType.TwoTwist ||
      type == AlgType.Parity;

  /// Begin a new case for [pair], baselined on [currentFacelets] (the cube's
  /// present physical state — the prior case's end state, or whatever the cube
  /// is at run start). Returns `false` if the pair has no expected-state
  /// geometry, in which case the case can't be cube-completed.
  bool startCase(String pair, String currentFacelets) {
    _baselines.clear();
    _expecteds.clear();
    _matched = null;
    _shownAt = _now();
    _firstMoveAt = null;
    _recognition = null;
    phase = CubePhase.recognition;
    return _addBaseline(pair, currentFacelets);
  }

  /// Replace the candidate set with a single baseline on [currentFacelets],
  /// e.g. after a resync or a baseline corrected before the case moved. Timing
  /// and phase are left untouched.
  void rebaseline(String pair, String currentFacelets) {
    _baselines.clear();
    _expecteds.clear();
    _matched = null;
    _addBaseline(pair, currentFacelets);
  }

  /// Add another candidate baseline on [facelets] — a mid-case rest (pause or
  /// botch) — keeping the earlier ones. De-dupes and preserves the case-start
  /// baseline when capping. Returns `false` if [pair] can't be mapped from here.
  bool addBaseline(String pair, String facelets) => _addBaseline(pair, facelets);

  bool _addBaseline(String pair, String facelets) {
    _pair = pair;
    if (_baselines.contains(facelets)) return _expecteds.isNotEmpty;
    final expected =
        ThreeStyleGeometry.expectedAfterPair(facelets, pair, algType);
    if (expected == null) return false;
    _baselines.add(facelets);
    _expecteds.add(expected);
    if (_baselines.length > _maxBaselines) {
      _baselines.removeAt(1); // keep the case-start baseline at index 0
      _expecteds.removeAt(1);
    }
    return true;
  }

  /// Feed a move. Returns the recognition split the instant the *first* move of
  /// the case lands (recognition ends there); `null` otherwise.
  Duration? onMove() {
    if (phase != CubePhase.recognition) return null;
    _firstMoveAt = _now();
    _recognition = _firstMoveAt!.difference(_shownAt!);
    phase = CubePhase.execution;
    return _recognition;
  }

  /// Feed a full-state snapshot. Returns the completed [CaseSplit] the instant
  /// the cube reaches an expected state (from any baseline); `null` while the
  /// case is unfinished. A match on a later baseline means stray moves are still
  /// on the cube: [CaseSplit.recovered].
  CaseSplit? onState(String facelets) {
    if (phase != CubePhase.execution) return null;
    final matched = _matchIndex(facelets);
    if (matched < 0) return null;
    _matched = facelets;
    final execution = _now().difference(_firstMoveAt!);
    phase = CubePhase.complete;
    return CaseSplit(_recognition!, execution, recovered: matched > 0);
  }

  // Which baseline the cube completed the case from, or -1. Parity is judged by
  // predicate — any rigid edge swap goes, so its end state isn't a fixed string
  // — every other type is exact state equality.
  int _matchIndex(String facelets) {
    final pair = _pair;
    if (algType != AlgType.Parity || pair == null) {
      return _expecteds.indexOf(facelets);
    }
    for (var i = 0; i < _baselines.length; i++) {
      if (ThreeStyleGeometry.isPairComplete(
          facelets, _baselines[i], pair, algType)) {
        return i;
      }
    }
    return -1;
  }

  /// The cube's end-state for the case: the state it completed on, else the
  /// case-start expected state; `null` if unmapped. Read it after a completion —
  /// parity's pre-completion value is only one of its legal end states.
  String? get expectedFacelets =>
      _matched ?? (_expecteds.isEmpty ? null : _expecteds.first);

  /// Every candidate baseline, oldest first; index 0 is the case-start state.
  /// Wrong-case feedback is judged against all of them, the same way completion
  /// is (see [ThreeStyleGeometry.executedOtherPair]).
  List<String> get baselines => List.unmodifiable(_baselines);

  /// The state the case was shown in; `null` before the case starts.
  String? get caseStartFacelets => _baselines.isEmpty ? null : _baselines.first;
}
