import 'dart:async' as async;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smartcube/smartcube.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:timer_count_down/timer_count_down.dart';

import '../alg_provider.dart';
import '../alg_structs.dart';
import '../equalizing_selector.dart';
import '../l10n/app_localizations.dart';
import '../practice_type.dart';
import '../settings.dart';
import '../smart_cube/cube_orientation.dart';
import '../smart_cube/cube_run.dart';
import '../smart_cube/move_reconstruction.dart';
import '../smart_cube/orientation_diagnostics.dart';
import '../smart_cube/three_style_geometry.dart';
import '../smart_cube_manager.dart';
import '../theme/app_palette.dart';
import '../theme/theme_scope.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/recording_dot.dart';
import 'session_summary_screen.dart';

const double MINIMUM_ALLOWED_TIME = 0.30; // to prevent misclick via double tap

class TimerScreen extends StatefulWidget {
  final PracticeType practiceType;
  final double targetTime;
  final double raceTime;
  final AlgProvider algProvider;
  final AlgType algType;
  final List<String> skippedAlgs;
  final int algsShownInAdvance;
  final bool recordTimes;

  TimerScreen(this.practiceType, this.targetTime, this.raceTime,
      this.algProvider, this.algType, this.algsShownInAdvance,
      {this.skippedAlgs = const [], this.recordTimes = true});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  bool isPressed = false;
  var stopwatch = Stopwatch();
  var times = <AlgTime>[];
  var skippedAlgs = <String>[];
  Alg? alg;
  var nextAlgs = <Alg>[];
  late async.Timer refreshTimer;
  DateTime? timerStartTime;
  bool isReady = false;

  // Cube-driven mode: a connected smart cube drives arming/advance instead of
  // press-and-release. Active only for alg types the geometry supports.
  late final bool _cubeMode;
  // The alg type driving cube geometry: the run's own type when supported, or —
  // for a custom set — the scheme its pairs were detected as. Null when the cube
  // can't drive this run (geometry paths use this, not widget.algType).
  AlgType? _cubeAlgType;
  CubeRunController? _cubeRun;
  async.StreamSubscription<CubeState>? _stateSub;
  async.StreamSubscription<CubeMove>? _moveSub;
  async.StreamSubscription<CubeState>? _resyncSub;
  // The cube dropped and is being reconnected: the run pauses until it is back.
  bool _reconnecting = false;
  // The link dropped: what the cube reports is stale until the resync re-anchors
  // us, and judging it meanwhile would abandon or falsely complete the case.
  bool _awaitingResync = false;

  _CubeFeedback? _feedback;
  // The feedback was carried over from the case that just went wrong; it stays
  // up on the new case until the user starts turning again.
  bool _carriedFeedback = false;
  // Un-normalised cube state at case start, for the orientation sweep.
  String? _caseRawStart;
  bool _orientationConfirmed = false;
  // The cube re-synced mid-case, so its time is no longer honest: don't record
  // it. Not a user mistake — it never reaches the summary's errors.
  bool _caseSpoiled = false;
  List<String> _pairPool = const [];
  // The target the run is judged against. Starts from the menu's value; editing
  // it on the summary updates it for the rest of the session, not just that one
  // summary.
  late double _targetTime = widget.targetTime;

  // Cases the user got wrong this run (cube-driven only); shown in the summary.
  final List<AlgMistake> mistakes = [];
  // Cases already written to the errors history this run, by row id. Forgetting
  // an alg and botching it three times in one session is one weak case, not
  // three, so a case gets a single row — the summary still shows every slip.
  final Map<String, int> _mistakeRows = {};
  final Map<String, AlgMistakeKind> _mistakeKinds = {};
  // Moves turned since the current case started, in the user's holding frame —
  // what a botched attempt actually did. Capped so a long flail can't grow
  // without bound.
  // Kept as raw CubeMoves, not notation: the slice reconstruction needs the
  // timestamps to tell a slice from two turns done at once, and the frame
  // correction is applied once over the whole sequence rather than per move.
  final List<CubeMove> _caseMoves = [];
  static const int _MAX_STORED_MOVES = 120;

  // How long the cube must sit still before a non-completing state is judged a
  // mistake. Algs are meant to flow, so a pause this long already means you've
  // stopped — waiting any longer just leaves the error hanging unexplained.
  static const Duration _FEEDBACK_QUIET_PERIOD = Duration(milliseconds: 500);
  async.Timer? _feedbackTimer;

  // Brief flash on auto-advance: green on a clean completion, red on an error.
  bool _advanceFlash = false;
  bool _flashError = false;
  async.Timer? _advanceFlashTimer;
  // Ignore the requeue button briefly after an auto-advance so a reflexive
  // press can't requeue the freshly-shown next case.
  bool _requeueBlocked = false;
  async.Timer? _requeueDebounce;

  // Records one solved case: appends to the session list and, for recording
  // runs, writes the DB row and nudges the selector. Shared by both timing modes.
  void _recordSolve(Alg solved, int elapsedMilliseconds, {int? recognitionMs}) {
    // The solve's timestamp; for recorded runs the same value is written to the
    // DB row, so the summary can delete that exact row.
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    times.add(AlgTime(times.length + 1, elapsedMilliseconds, solved,
        timestamp: timestamp, recognitionMs: recognitionMs));
    if (_isRecordingRun) {
      DatabaseManager().insertResult(
          widget.algType, solved.name, elapsedMilliseconds,
          timestamp: timestamp, recognitionMs: recognitionMs);
      // Keep the selector's weights fresh across a long "again" chain.
      final provider = widget.algProvider;
      if (provider is EqualizingSelector) {
        provider.recordSolve(solved.name);
      }
    }
  }

  void _onTapDown() {
    if (_cubeMode ||
        !isReady ||
        isPressed ||
        alg == null ||
        stopwatch.elapsedMilliseconds / 1000 < MINIMUM_ALLOWED_TIME) {
      return;
    }

    setState(() {
      isPressed = true;
      stopwatch.stop();
      _recordSolve(alg!, stopwatch.elapsedMilliseconds);
    });
  }

  void _onTapUp() async {
    if (_cubeMode || !isReady || alg == null || !isPressed) {
      return;
    }

    List<AlgTime> timesCopy = List.from(times);
    int totalTimeMs = _elapsedSessionMs();

    setState(() {
      isPressed = false;
      stopwatch.reset();

      Alg? nextAlg = _fetchNextAlg();
      if (nextAlg != null) {
        nextAlgs.insert(0, nextAlg);
      }
      alg = nextAlgs.isEmpty ? null : nextAlgs.removeLast();
      if (alg == null) {
        if (widget.practiceType.isSetBased) {
          // Pool exhausted, stop
          times.clear();
          timerStartTime = null;
        }
      } else {
        stopwatch.start();
      }
    });

    if (alg == null) {
      final result = await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => _buildSummary(timesCopy, totalTimeMs)));

      setState(() {
        isReady = false;
      });

      if (result == "repeat_all") {
        widget.algProvider.reset(skippedAlgs: skippedAlgs);
      } else if (result == "repeat_target_time") {
        for (AlgTime algTime in timesCopy) {
          if (isUnderTargetTime(algTime.timeMs, _targetTime)) {
            skippedAlgs.add(algTime.alg.name);
          }
        }
        widget.algProvider.reset(skippedAlgs: skippedAlgs);
      } else {
        if (mounted && context.mounted) {
          Navigator.pop(context);
        }
      }
    }
  }

  bool get _isRecordingRun => isRecordingRun(
        practiceType: widget.practiceType,
        algType: widget.algType,
        algsShownInAdvance: widget.algsShownInAdvance,
        recordTimes: widget.recordTimes,
      );

  // Deletion of recorded rows is wired only for recording runs; a non-recording
  // summary gets no delete callbacks (swiping there just explains why).
  SessionSummaryScreen _buildSummary(List<AlgTime> algTimes, int totalTimeMs,
      {List<AlgMistake> algMistakes = const []}) {
    final recording = _isRecordingRun;
    return SessionSummaryScreen(
      algTimes: algTimes,
      mistakes: algMistakes,
      cubeDriven: _cubeMode,
      algType: widget.algType,
      targetTime: _targetTime,
      onTargetTimeChanged: (t) => setState(() => _targetTime = t),
      practiceType: widget.practiceType,
      totalTimeMs: totalTimeMs,
      onDeleteFromDb: recording
          ? (t) => DatabaseManager().deleteRecordedResult(
              widget.algType, t.alg.name, t.timeMs, t.timestamp)
          : null,
      onRestoreToDb: recording
          ? (t) => DatabaseManager().insertResult(
              widget.algType, t.alg.name, t.timeMs,
              timestamp: t.timestamp, recognitionMs: t.recognitionMs)
          : null,
    );
  }

  Alg? _fetchNextAlg() {
    if (widget.practiceType == PracticeType.timeRace) {
      return widget.algProvider.getNextAlg();
    }

    Alg? nextAlg;
    do {
      nextAlg = widget.algProvider.getNextAlg();
    } while (nextAlg != null && skippedAlgs.contains(nextAlg.name));
    return nextAlg;
  }

  // ---- Cube-driven mode ----------------------------------------------------

  // The alg type whose geometry drives cube-completion, or null if the cube
  // can't drive this run. A custom set is matched against the known schemes; a
  // supported type drives itself only if its pairs actually map (parity needs
  // the edge buffer adjacent to the corner buffer, else it's unmappable).
  AlgType? _resolveCubeAlgType(SmartCubeManager mgr) {
    if (!mgr.isConnected) return null;
    if (widget.algType == AlgType.Custom) {
      return ThreeStyleGeometry.detectAlgType(_customPairs);
    }
    if (!CubeRunController.supports(widget.algType)) return null;
    final pool = enumerateAlgs(widget.algType);
    final mappable = pool.isNotEmpty &&
        pool.every((p) => ThreeStyleGeometry.expectedAfterPair(
                CubeState.solvedFacelets, p, widget.algType) !=
            null);
    return mappable ? widget.algType : null;
  }

  List<String> get _customPairs {
    final p = widget.algProvider;
    return p is CustomProvider ? p.letterPairs : const [];
  }

  String get _rawFacelets =>
      SmartCubeManager().cube?.currentState.facelets ??
      CubeState.solvedFacelets;

  String get _currentFacelets => _normalise(_rawFacelets);

  // Into the standard frame the geometry assumes, per the orientation setting.
  String _normalise(String facelets) => CubeOrientation.normaliseFacelets(
        facelets,
        top: Settings().getCubeTopColour(),
        front: Settings().getCubeFrontColour(),
      );

  void _onCubeState(CubeState state) {
    if (!mounted || !isReady || _awaitingResync) return;
    final norm = _normalise(state.facelets);
    final split = _cubeRun?.onState(norm);
    if (split != null) {
      _onCubeComplete(split);
      return;
    }
    _scheduleFeedback(state.facelets, norm);
  }

  // Diagnose only once the turning stops. Many algs pass *through* another
  // case's finished state on the way — DG's alg is a prefix of DB's — so a
  // match seen mid-execution means nothing, and acting on it would abandon a
  // case the user is executing correctly. Every move restarts the wait.
  void _scheduleFeedback(String rawFacelets, String normFacelets) {
    _feedbackTimer?.cancel();
    _feedbackTimer = async.Timer(_FEEDBACK_QUIET_PERIOD, () {
      if (!mounted || !isReady) return;
      _updateFeedback(rawFacelets, normFacelets);
    });
  }

  // Hint whether a non-completing state means a different case (wrong pair) or
  // the right case in the wrong orientation. Orientation is checked only until
  // the first correct completion, and takes priority over the wrong-pair guess.
  // Hints are sticky (kept until the case completes or a new one starts).
  void _updateFeedback(String rawFacelets, String normFacelets) {
    final shown = alg?.name;
    final start = _cubeRun?.startFacelets;
    if (shown == null || start == null) return;

    if (!_orientationConfirmed && _caseRawStart != null) {
      final o = detectExecutedOrientation(
        rawStart: _caseRawStart!,
        rawEnd: rawFacelets,
        pair: shown,
        algType: _cubeAlgType!,
      );
      final current =
          (Settings().getCubeTopColour(), Settings().getCubeFrontColour());
      if (o != null && o != current) {
        _setFeedback(_CubeFeedback.orientation(shown, o.$1, o.$2));
        return;
      }
    }

    final wrong = ThreeStyleGeometry.matchingPair(
        normFacelets, start, _cubeAlgType!, _pairPool);
    if (wrong != null && wrong != shown) {
      _onCubeError(shown, AlgMistakeKind.wrongCase, executed: wrong);
    }
  }

  // A mistake ends the case: log it, put it back in the pool and move straight
  // on (red flash), baselining the next case on wherever the cube now is. The
  // message carries over so it can still be read once the next case is up.
  void _onCubeError(String shown, AlgMistakeKind kind, {String? executed}) {
    final moves = MoveReconstruction.describe(_caseMoves,
        cube: SmartCubeManager().cube);
    mistakes.add(AlgMistake(mistakes.length + 1, Alg(shown), kind,
        executed: executed, moves: moves));
    if (widget.algType != AlgType.Custom) {
      _persistMistake(shown, kind, executed, moves);
    }
    // Skip drops the case from the rest of the run; every other error puts it
    // back in the pool to be retried later.
    final skipping = kind == AlgMistakeKind.skipped;
    if (skipping) widget.algProvider.skip(shown);
    _advanceCubeCase(_currentFacelets,
        requeueAfter: skipping ? null : shown,
        keepFeedback:
            executed == null ? null : _CubeFeedback.wrongCase(executed));
    _flashAdvance(error: true);
    _blockRequeueBriefly();
  }

  // Errors are worth keeping whatever the run's timing settings — unlike a time,
  // a wrong pair is a wrong pair. One row per case per run: a repeat slip on a
  // case only refines the row, upward only — a named wrong pair beats a bare
  // requeue or skip, and a terminal skip beats a requeue.
  static const _mistakeRank = {
    AlgMistakeKind.requeued: 0,
    AlgMistakeKind.skipped: 1,
    AlgMistakeKind.wrongCase: 2,
  };

  void _persistMistake(
      String pair, AlgMistakeKind kind, String? executed, String? moves) async {
    final db = DatabaseManager();
    if (!_mistakeRows.containsKey(pair)) {
      final id = await db.insertMistake(widget.algType, pair, kind,
          executed: executed, moves: moves);
      if (id != null) {
        _mistakeRows[pair] = id;
        _mistakeKinds[pair] = kind;
      }
      return;
    }
    if (_mistakeRank[kind]! > _mistakeRank[_mistakeKinds[pair]]!) {
      _mistakeKinds[pair] = kind;
      await db.updateMistake(_mistakeRows[pair]!, kind,
          executed: executed, moves: moves);
    }
  }

  void _setFeedback(_CubeFeedback fb) {
    if (fb != _feedback) setState(() => _feedback = fb);
  }

  void _onCubeMove(CubeMove move) {
    if (!mounted || !isReady || _awaitingResync) return;
    // Still turning: whatever the last state looked like, it wasn't the end.
    _feedbackTimer?.cancel();
    if (_caseMoves.length < _MAX_STORED_MOVES) _caseMoves.add(move);
    // First move of a case ends recognition; refresh the phase indicator.
    final started = _cubeRun?.onMove() != null;
    // Turning again means the carried-over error message has served its purpose.
    if (_carriedFeedback) {
      _carriedFeedback = false;
      setState(() => _feedback = null);
    } else if (started) {
      setState(() {});
    }
  }

  // Arm from the cube's current physical state (no forced solve) once the
  // get-ready countdown finishes.
  void _armCubeRun() {
    setState(() {
      isReady = true;
      isPressed = false;
      timerStartTime = DateTime.now();
      times.clear();
      mistakes.clear();
      _mistakeRows.clear();
      _mistakeKinds.clear();
      nextAlgs.clear();
      _orientationConfirmed = false;
      _startCubeCase(_currentFacelets);
    });
  }

  // Show the next case and baseline its completion check on [fromFacelets]
  // (solved for the first case, the prior case's end state afterward). When
  // [requeueAfter] is set, that case is re-inserted only *after* the next one is
  // drawn, so a requeued case never comes straight back — unless it was the last
  // remaining case, in which case there's nothing else and it returns now.
  void _startCubeCase(String fromFacelets,
      {String? requeueAfter, _CubeFeedback? keepFeedback}) {
    _feedbackTimer?.cancel();
    _feedback = keepFeedback;
    _carriedFeedback = keepFeedback != null;
    _caseSpoiled = false;
    _caseMoves.clear();
    _caseRawStart = _rawFacelets;
    alg = _fetchNextAlg();
    if (requeueAfter != null) {
      widget.algProvider.requeue(requeueAfter);
      alg ??= _fetchNextAlg();
    }
    if (alg == null) return;
    _cubeRun!.startCase(alg!.name, fromFacelets);
    _verifyBaseline(alg!.name);
    stopwatch
      ..reset()
      ..start();
  }

  // Trust the cube over our own bookkeeping: pull its real state as the case
  // opens, so drift we failed to notice costs one baseline instead of the whole
  // session. Silent — the user has nothing to fix.
  void _verifyBaseline(String pair) async {
    final cube = SmartCubeManager().cube;
    if (cube == null) return;
    final state = await cube.requestState();
    if (!mounted || alg?.name != pair) return;
    // Left alone only if the case hasn't started moving; mid-execution the
    // baseline is what the split is measured against.
    if (_cubeRun!.phase != CubePhase.recognition) return;
    final norm = _normalise(state.facelets);
    if (norm == _cubeRun!.startFacelets) return;
    _cubeRun!.rebaseline(pair, norm);
    _caseRawStart = state.facelets;
  }

  void _onCubeComplete(CaseSplit split) {
    final finished = alg;
    if (finished == null) return;
    final spoiled = _caseSpoiled; // starting the next case clears the flag
    stopwatch.stop();
    setState(() {
      _orientationConfirmed = true; // a clean solve proves the orientation
      _feedback = null;
      if (!spoiled) {
        _recordSolve(finished, split.total.inMilliseconds,
            recognitionMs: split.recognition.inMilliseconds);
      }
    });
    // A resync cost the case its honest time: no mistake, but no time either —
    // so back in the pool rather than dropped from the run.
    _advanceCubeCase(_cubeRun!.expectedFacelets ?? _currentFacelets,
        requeueAfter: spoiled ? finished.name : null);
    _flashAdvance();
    _blockRequeueBriefly();
  }

  // Quick, faint blip on auto-advance: green validates a completion, red an
  // error (held a little longer, since it's the bad news).
  void _flashAdvance({bool error = false}) {
    _advanceFlashTimer?.cancel();
    setState(() {
      _advanceFlash = true;
      _flashError = error;
    });
    _advanceFlashTimer =
        async.Timer(Duration(milliseconds: error ? 180 : 70), () {
      if (mounted) setState(() => _advanceFlash = false);
    });
  }

  void _blockRequeueBriefly() {
    _requeueDebounce?.cancel();
    setState(() => _requeueBlocked = true);
    _requeueDebounce = async.Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _requeueBlocked = false);
    });
  }

  // The manual escape hatch: the case was botched into a state the cube can't
  // name, so the user says so. Counts as a mistake and goes back in the pool.
  void _requeueCubeCase() {
    if (!isReady || alg == null || _requeueBlocked) return;
    _onCubeError(alg!.name, AlgMistakeKind.requeued);
  }

  // Give up on the case: log it as a mistake and move on without putting it
  // back, so a set can end without a deliberate wrong solve and time race won't
  // show it again this session.
  void _skipCubeCase() {
    if (!isReady || alg == null || _requeueBlocked) return;
    _onCubeError(alg!.name, AlgMistakeKind.skipped);
  }

  // A settings fix, not a mistake: the case is requeued but nothing is logged.
  void _applyDetectedOrientation(CubeColour top, CubeColour front) {
    Settings().setCubeOrientation(top, front);
    _advanceCubeCase(_currentFacelets, requeueAfter: alg?.name);
  }

  void _advanceCubeCase(String fromFacelets,
      {String? requeueAfter, _CubeFeedback? keepFeedback}) {
    setState(() {
      stopwatch
        ..stop()
        ..reset();
      _startCubeCase(fromFacelets,
          requeueAfter: requeueAfter, keepFeedback: keepFeedback);
    });
    // Sets/slowest end when the pool is exhausted; time race ends on the timer.
    if (alg == null && widget.practiceType.isSetBased) {
      _finishCubeSession();
    }
  }

  void _finishCubeSession() async {
    List<AlgTime> timesCopy = List.from(times);
    List<AlgMistake> mistakesCopy = List.from(mistakes);
    int totalTimeMs = _elapsedSessionMs();
    setState(() {
      times.clear();
      mistakes.clear();
      nextAlgs.clear();
      timerStartTime = null;
    });
    await _showSummaryAndReset(timesCopy, totalTimeMs, mistakesCopy);
  }

  // Shared summary navigation + repeat handling for cube-driven sessions
  // (mirrors the press/release flows, unified for sets and time race).
  Future<void> _showSummaryAndReset(List<AlgTime> timesCopy, int totalTimeMs,
      List<AlgMistake> mistakesCopy) async {
    final result = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => _buildSummary(timesCopy, totalTimeMs,
                algMistakes: mistakesCopy)));
    if (!mounted) return;
    setState(() {
      isReady = false;
    });
    if (result == "repeat_all" || result == "again") {
      widget.algProvider.reset(skippedAlgs: skippedAlgs);
    } else if (result == "repeat_target_time") {
      for (AlgTime algTime in timesCopy) {
        if (isUnderTargetTime(algTime.timeMs, _targetTime)) {
          skippedAlgs.add(algTime.alg.name);
        }
      }
      widget.algProvider.reset(skippedAlgs: skippedAlgs);
    } else if (context.mounted) {
      Navigator.pop(context);
    }
  }

  void _onConnectionChanged() {
    if (!mounted) return;
    final c = SmartCubeManager().connection.value;
    if (c == CubeConnection.disconnected) {
      // The cube drives this screen; without it, drop back to the menu.
      Navigator.pop(context);
      return;
    }
    // A dropped link is usually the cube napping — hold the run and wait for the
    // manager to bring it back rather than throwing the session away.
    final reconnecting =
        c == CubeConnection.lost || c == CubeConnection.reconnecting;
    if (reconnecting) {
      _awaitingResync = true;
      _feedbackTimer?.cancel();
    }
    if (reconnecting != _reconnecting) setState(() => _reconnecting = reconnecting);
  }

  // Tracking was re-anchored on the cube's real state: moves happened that we
  // never saw, so the current case's baseline is meaningless. Re-baseline onto
  // where the cube actually is and let the user execute the shown pair from
  // there — and don't record the case, since its time is no longer honest.
  void _onCubeResync(CubeState state) {
    if (!mounted) return;
    _awaitingResync = false;
    if (!isReady) return;
    final shown = alg?.name;
    if (shown == null) return;
    final norm = _normalise(state.facelets);
    _cubeRun!.rebaseline(shown, norm);
    _caseRawStart = state.facelets;
    _caseSpoiled = true;
    // Moves were missed, so what we collected no longer describes the attempt.
    _caseMoves.clear();
    _feedbackTimer?.cancel();
    _setFeedback(_CubeFeedback.resynced());
  }

  void _onTimeRaceEnded() async {
    List<AlgTime> timesCopy = List.from(times);
    List<AlgMistake> mistakesCopy = List.from(mistakes);
    int totalTimeMs = _elapsedSessionMs();
    setState(() {
      isPressed = false;
      stopwatch.stop();
      stopwatch.reset();
      times.clear();
      mistakes.clear();
      nextAlgs.clear();
      timerStartTime = null;
    });

    final result = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => _buildSummary(timesCopy, totalTimeMs,
                algMistakes: mistakesCopy)));

    setState(() {
      isReady = false;
    });

    if (result == "again") {
      widget.algProvider.reset(skippedAlgs: skippedAlgs);
    } else if (mounted && context.mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void initState() {
    super.initState();

    skippedAlgs = List.of(widget.skippedAlgs);

    final mgr = SmartCubeManager();
    _cubeAlgType = _resolveCubeAlgType(mgr);
    _cubeMode = _cubeAlgType != null;
    if (_cubeMode) {
      _cubeRun = CubeRunController(_cubeAlgType!);
      _pairPool = enumerateAlgs(_cubeAlgType!);
      // The manager's streams, not the cube's: a reconnect swaps the SmartCube
      // underneath and these keep flowing.
      _stateSub = mgr.states.listen(_onCubeState);
      _moveSub = mgr.moves.listen(_onCubeMove);
      _resyncSub = mgr.resyncs.listen(_onCubeResync);
      mgr.connection.addListener(_onConnectionChanged);
    } else if (mgr.isConnected) {
      // Cube connected but this run isn't cube-drivable. Parity is unmappable
      // only when the edge buffer isn't adjacent to the corner buffer — say so
      // precisely; anything else is an unrecognized letter-pair scheme.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.algType == AlgType.Parity
              ? l10n.smartCubeParityBuffersNotAdjacent
              : l10n.smartCubeSchemeUnrecognized),
          duration: const Duration(seconds: 5),
        ));
      });
    }

    refreshTimer = async.Timer.periodic(
        Duration(milliseconds: 50),
        (async.Timer t) => setState(() {
              if (widget.practiceType == PracticeType.timeRace) {
                if (getTimeRaceProgression() >= 1 && timerStartTime != null) {
                  _onTimeRaceEnded();
                }
              }
            }));
    ServicesBinding.instance.keyboard.addHandler(_onKey);
  }

  @override
  void dispose() {
    super.dispose();
    refreshTimer.cancel();
    _advanceFlashTimer?.cancel();
    _requeueDebounce?.cancel();
    _feedbackTimer?.cancel();
    _stateSub?.cancel();
    _moveSub?.cancel();
    _resyncSub?.cancel();
    SmartCubeManager().connection.removeListener(_onConnectionChanged);
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (_cubeMode || LogicalKeyboardKey.space != event.logicalKey) {
      return false;
    }
    if (event is KeyDownEvent) {
      // Key-down while still "pressed" means the key-up was dropped; release
      // first so the timer can't get stuck. (Repeats are KeyRepeatEvent.)
      if (isPressed) {
        _onTapUp();
      } else {
        _onTapDown();
      }
    } else if (event is KeyUpEvent) {
      _onTapUp();
    }
    return false;
  }

  TextSpan getAlgTextSpan(ThemeData theme, String algChar, TextStyle style) {
    Set<String> greenCharacters = {'é', 'É'};
    Set<String> redCharacters = {'è', 'È'};

    if (greenCharacters.contains(algChar)) {
      return TextSpan(
        text: algChar,
        style: style.copyWith(color: Colors.green),
      );
    } else if (redCharacters.contains(algChar)) {
      return TextSpan(
        text: algChar,
        style: style.copyWith(color: Colors.orange),
      );
    } else {
      return TextSpan(
        text: algChar,
        style: style,
      );
    }
  }

  // Wall-clock time from countdown finish to session end (0 if not started).
  int _elapsedSessionMs() {
    if (timerStartTime == null) {
      return 0;
    }
    return DateTime.now().difference(timerStartTime!).inMilliseconds;
  }

  double getTimeRaceProgression() {
    if (timerStartTime == null) {
      return 0;
    }
    Duration duration = DateTime.now().difference(timerStartTime!);
    int ms = duration.inMilliseconds;
    double progression = 1;
    if (widget.raceTime > 0) {
      progression = ms / (widget.raceTime * 60 * 1000);
    }
    return progression;
  }

  String _title(BuildContext context) =>
      sessionTitle(context, widget.algType, widget.practiceType);

  // Get-ready countdown before a cube-driven run arms. Arms from the cube's
  // current state, so no forced solve between runs.
  Widget _buildCubeCountdown(ThemeData theme, AppPalette p) {
    return Center(
      child: Countdown(
        seconds: 3,
        build: (BuildContext context, double time) => Text(
          time.ceil() > 0 ? time.ceil().toString() : "",
          style: theme.textTheme.displayLarge?.copyWith(color: p.accent),
        ),
        interval: Duration(milliseconds: 100),
        onFinished: _armCubeRun,
      ),
    );
  }

  // In-run panel: the cube drives timing/advance; taps are inert and a "Redo
  // later" button plus wrong-case/orientation hints are the only manual controls.
  Widget _buildCubeRun(
      ThemeData theme, AppPalette p, double progress, String timerText) {
    final l10n = AppLocalizations.of(context)!;
    final phase = _cubeRun?.phase ?? CubePhase.recognition;
    final phaseLabel = phase == CubePhase.execution
        ? l10n.smartCubeExecution
        : l10n.smartCubeRecognition;
    final Widget run = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: p.panelBorder,
              color: p.accent,
            ),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var nextAlg in nextAlgs)
                RichText(
                    text: TextSpan(
                        children: nextAlg.name.characters
                            .map((e) => getAlgTextSpan(
                                theme,
                                e,
                                theme.textTheme.displaySmall!.copyWith(
                                    color: p.textFaint, letterSpacing: 2)))
                            .toList())),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  children: (alg != null ? alg!.name : "--")
                      .characters
                      .map((e) =>
                          getAlgTextSpan(theme, e, theme.textTheme.displayLarge!))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                phaseLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                    color: phase == CubePhase.execution ? p.accent : p.textFaint,
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 12),
              Text(
                timerText,
                style: theme.textTheme.displayMedium?.copyWith(color: p.pop),
              ),
              _buildCubeFeedback(l10n, p),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _requeueBlocked || _reconnecting
                      ? null
                      : _requeueCubeCase,
                  icon: const Icon(Icons.replay),
                  label: Text(l10n.smartCubeRequeue),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _requeueBlocked || _reconnecting ? null : _skipCubeCase,
                  icon: const Icon(Icons.skip_next),
                  label: Text(l10n.smartCubeSkip),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Stack(
      children: [
        run,
        if (_advanceFlash)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                  color: _flashError
                      ? p.bad.withValues(alpha: 0.16)
                      : p.good.withValues(alpha: 0.09)),
            ),
          ),
        if (_reconnecting) Positioned.fill(child: _reconnectingOverlay(p)),
      ],
    );
  }

  // The cube nodded off (or wandered out of range). Hold the run here — turning
  // a face wakes it and the manager reconnects, then the case re-baselines.
  Widget _reconnectingOverlay(AppPalette p) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: p.surfaceOpaque.withValues(alpha: 0.88),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: p.accent),
          const SizedBox(height: 20),
          Text(l10n.smartCubeReconnecting,
              style: TextStyle(fontSize: 20, color: p.textPrimary)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(l10n.smartCubeReconnectingHint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildCubeFeedback(AppLocalizations l10n, AppPalette p) {
    final fb = _feedback;
    if (fb == null) return const SizedBox.shrink();
    final textStyle = TextStyle(
        color: p.bad, fontSize: 22, fontWeight: FontWeight.w400, height: 1.15);
    if (fb.isOrientation) {
      final top = cubeColourName(l10n, fb.top!);
      final front = cubeColourName(l10n, fb.front!);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          children: [
            Text(
              l10n.smartCubeWrongOrientation(fb.pair, top, front),
              textAlign: TextAlign.center,
              style: textStyle,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => _applyDetectedOrientation(fb.top!, fb.front!),
              icon: const Icon(Icons.screen_rotation_alt, size: 18),
              label: Text(l10n.smartCubeSwitchOrientation(top, front)),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Text(
        fb.isResynced ? l10n.smartCubeResynced : l10n.smartCubeWrongCase(fb.pair),
        textAlign: TextAlign.center,
        style: textStyle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;

    var timerText = timeToString(stopwatch.elapsedMilliseconds);
    final progress = widget.practiceType.isSetBased
        ? widget.algProvider
            .getProgression(preFetchedAlgsCount: nextAlgs.length)
        : getTimeRaceProgression();

    final Widget content = _cubeMode
        ? (isReady
            ? _buildCubeRun(theme, p, progress, timerText)
            : _buildCubeCountdown(theme, p))
        : isReady
        ? Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _onTapDown(),
            onPointerUp: (_) => _onTapUp(),
            child: Stack(
              children: [
                // Subtle press feedback flash.
                if (isPressed)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(color: p.pop.withValues(alpha: 0.10)),
                    ),
                  ),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          backgroundColor: p.panelBorder,
                          color: p.accent,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var nextAlg in nextAlgs)
                            RichText(
                                text: TextSpan(
                                    children: nextAlg.name.characters
                                        .map((e) => getAlgTextSpan(
                                            theme,
                                            e,
                                            theme.textTheme.displaySmall!
                                                .copyWith(
                                                    color: p.textFaint,
                                                    letterSpacing: 2)))
                                        .toList())),
                          const SizedBox(height: 8),
                          RichText(
                            text: TextSpan(
                              children: (alg != null ? alg!.name : "--")
                                  .characters
                                  .map((e) => getAlgTextSpan(
                                      theme, e, theme.textTheme.displayLarge!))
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            timerText,
                            style: theme.textTheme.displayMedium
                                ?.copyWith(color: p.pop),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        : Center(
            child: Countdown(
              seconds: 3,
              build: (BuildContext context, double time) => Text(
                time.ceil() > 0 ? time.ceil().toString() : "",
                style: theme.textTheme.displayLarge?.copyWith(color: p.accent),
              ),
              interval: Duration(milliseconds: 100),
              onFinished: () {
                setState(() {
                  isReady = true;
                  isPressed = false;
                  timerStartTime = DateTime.now();
                  nextAlgs.clear();
                  for (int i = 0; i < widget.algsShownInAdvance; ++i) {
                    Alg? nextAlg = _fetchNextAlg();
                    if (nextAlg != null) {
                      nextAlgs.add(nextAlg);
                    }
                  }
                  alg = _fetchNextAlg();
                  if (alg == null) {
                    assert(nextAlgs.isNotEmpty);
                    alg = nextAlgs.removeLast();
                  }

                  stopwatch.start();
                });
              },
            ),
          );

    final showDot = _isRecordingRun && Settings().getShowRecordingDot();
    return AppScaffold(
      title: _title(context),
      titleLeading: showDot ? const RecordingDot() : null,
      body: content,
    );
  }
}

enum _FeedbackKind { wrongCase, orientation, resynced }

class _CubeFeedback {
  final _FeedbackKind kind;
  final String pair;
  final CubeColour? top;
  final CubeColour? front;

  const _CubeFeedback.wrongCase(this.pair)
      : kind = _FeedbackKind.wrongCase,
        top = null,
        front = null;
  const _CubeFeedback.orientation(this.pair, this.top, this.front)
      : kind = _FeedbackKind.orientation;
  const _CubeFeedback.resynced()
      : kind = _FeedbackKind.resynced,
        pair = "",
        top = null,
        front = null;

  bool get isOrientation => kind == _FeedbackKind.orientation;
  bool get isResynced => kind == _FeedbackKind.resynced;

  @override
  bool operator ==(Object o) =>
      o is _CubeFeedback &&
      o.kind == kind &&
      o.pair == pair &&
      o.top == top &&
      o.front == front;

  @override
  int get hashCode => Object.hash(kind, pair, top, front);
}
