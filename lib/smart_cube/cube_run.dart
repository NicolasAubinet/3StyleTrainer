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
  const CaseSplit(this.recognition, this.execution);

  Duration get total => recognition + execution;
}

/// Drives the cube-side of a case: split each case into recognition (pair shown
/// → first move) and execution (first move → expected state), and detect correct
/// completion. Pure Dart and UI-agnostic — the widget feeds it moves/states and
/// reacts to the returned events.
///
/// Completion is judged by *state*, relative to wherever the cube starts: a case
/// is done only when the cube reaches `Δ_pair ∘ startState` (see
/// [ThreeStyleGeometry]). Because the check is relative, a run can begin from any
/// state (no forced solve between runs). A wrong alg never reaches that state, so
/// it can never auto-advance. Only Corner/Edge pairs are supported ([supports]);
/// other alg types have no expected-state geometry yet.
class CubeRunController {
  final AlgType algType;
  final DateTime Function() _now;

  CubeRunController(this.algType, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  CubePhase phase = CubePhase.idle;

  String? _startFacelets; // S — baseline at case start
  String? _expected; // E = Δ_pair ∘ S
  DateTime? _shownAt;
  DateTime? _firstMoveAt;
  Duration? _recognition;

  /// Whether cube-driven completion is available for [type] (Corner/Edge only).
  static bool supports(AlgType type) =>
      type == AlgType.Corner || type == AlgType.Edge;

  /// Begin a new case for [pair], baselined on [currentFacelets] (the cube's
  /// present physical state — the prior case's end state, or whatever the cube
  /// is at run start). Returns `false` if the pair has no expected-state
  /// geometry, in which case the case can't be cube-completed.
  bool startCase(String pair, String currentFacelets) {
    _startFacelets = currentFacelets;
    _expected =
        ThreeStyleGeometry.expectedAfterPair(currentFacelets, pair, algType);
    _shownAt = _now();
    _firstMoveAt = null;
    _recognition = null;
    phase = CubePhase.recognition;
    return _expected != null;
  }

  // Move the baseline onto [currentFacelets] (after a wrong case) so the shown
  // pair can be executed from here; timing and phase are left untouched.
  void rebaseline(String pair, String currentFacelets) {
    _startFacelets = currentFacelets;
    _expected =
        ThreeStyleGeometry.expectedAfterPair(currentFacelets, pair, algType);
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
  /// the cube reaches the expected state; `null` while the case is unfinished.
  CaseSplit? onState(String facelets) {
    if (phase != CubePhase.execution || _expected == null) return null;
    if (facelets != _expected) return null;
    final execution = _now().difference(_firstMoveAt!);
    phase = CubePhase.complete;
    return CaseSplit(_recognition!, execution);
  }

  /// The cube's expected end-state for the current case, or `null` if unmapped.
  String? get expectedFacelets => _expected;

  /// The current case's baseline (start) facelets.
  String? get startFacelets => _startFacelets;
}
