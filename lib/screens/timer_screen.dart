import 'dart:async' as async;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  CubeRunController? _cubeRun;
  async.StreamSubscription<CubeState>? _stateSub;
  async.StreamSubscription<CubeMove>? _moveSub;

  // Records one solved case: appends to the session list and, for recording
  // runs, writes the DB row and nudges the selector. Shared by both timing modes.
  void _recordSolve(Alg solved, int elapsedMilliseconds) {
    // The solve's timestamp; for recorded runs the same value is written to the
    // DB row, so the summary can delete that exact row.
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    times.add(AlgTime(times.length + 1, elapsedMilliseconds, solved,
        timestamp: timestamp));
    if (_isRecordingRun) {
      DatabaseManager().insertResult(
          widget.algType, solved.name, elapsedMilliseconds,
          timestamp: timestamp);
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
        final prefs = await SharedPreferences.getInstance();
        final target = prefs.getDouble("target_time") ?? widget.targetTime;
        for (AlgTime algTime in timesCopy) {
          if (isUnderTargetTime(algTime.timeMs, target)) {
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
  SessionSummaryScreen _buildSummary(List<AlgTime> algTimes, int totalTimeMs) {
    final recording = _isRecordingRun;
    return SessionSummaryScreen(
      algTimes: algTimes,
      algType: widget.algType,
      targetTime: widget.targetTime,
      practiceType: widget.practiceType,
      totalTimeMs: totalTimeMs,
      onDeleteFromDb: recording
          ? (t) => DatabaseManager().deleteRecordedResult(
              widget.algType, t.alg.name, t.timeMs, t.timestamp)
          : null,
      onRestoreToDb: recording
          ? (t) => DatabaseManager().insertResult(
              widget.algType, t.alg.name, t.timeMs,
              timestamp: t.timestamp)
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

  String get _currentFacelets => _normalise(
      SmartCubeManager().cube?.currentState.facelets ??
          CubeState.solvedFacelets);

  // Rotate the cube's reported state into the standard frame the geometry
  String _normalise(String facelets) => CubeOrientation.normaliseFacelets(
        facelets,
        top: Settings().getCubeTopColour(),
        front: Settings().getCubeFrontColour(),
      );

  void _onCubeState(CubeState state) {
    if (!mounted || !isReady) return;
    final split = _cubeRun?.onState(_normalise(state.facelets));
    if (split != null) _onCubeComplete(split);
  }

  void _onCubeMove() {
    if (!mounted || !isReady) return;
    // First move of a case ends recognition; refresh the phase indicator.
    if (_cubeRun?.onMove() != null) setState(() {});
  }

  // Arm from the cube's current physical state (no forced solve) once the
  // get-ready countdown finishes.
  void _armCubeRun() {
    setState(() {
      isReady = true;
      isPressed = false;
      timerStartTime = DateTime.now();
      times.clear();
      nextAlgs.clear();
      _startCubeCase(_currentFacelets);
    });
  }

  // Show the next case and baseline its completion check on [fromFacelets]
  // (solved for the first case, the prior case's end state afterward).
  void _startCubeCase(String fromFacelets) {
    alg = _fetchNextAlg();
    if (alg == null) return;
    _cubeRun!.startCase(alg!.name, fromFacelets);
    stopwatch
      ..reset()
      ..start();
  }

  void _onCubeComplete(CaseSplit split) {
    final finished = alg;
    if (finished == null) return;
    stopwatch.stop();
    setState(() {
      _recordSolve(finished, split.total.inMilliseconds);
    });
    _advanceCubeCase(_cubeRun!.expectedFacelets ?? _currentFacelets);
  }

  void _skipCubeCase() {
    if (!isReady || alg == null) return;
    // Skip records nothing; rebaseline on the cube's current physical state.
    _advanceCubeCase(_currentFacelets);
  }

  void _advanceCubeCase(String fromFacelets) {
    setState(() {
      stopwatch
        ..stop()
        ..reset();
      _startCubeCase(fromFacelets);
    });
    // Sets/slowest end when the pool is exhausted; time race ends on the timer.
    if (alg == null && widget.practiceType.isSetBased) {
      _finishCubeSession();
    }
  }

  void _finishCubeSession() async {
    List<AlgTime> timesCopy = List.from(times);
    int totalTimeMs = _elapsedSessionMs();
    setState(() {
      times.clear();
      nextAlgs.clear();
      timerStartTime = null;
    });
    await _showSummaryAndReset(timesCopy, totalTimeMs);
  }

  // Shared summary navigation + repeat handling for cube-driven sessions
  // (mirrors the press/release flows, unified for sets and time race).
  Future<void> _showSummaryAndReset(
      List<AlgTime> timesCopy, int totalTimeMs) async {
    final result = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => _buildSummary(timesCopy, totalTimeMs)));
    if (!mounted) return;
    setState(() {
      isReady = false;
    });
    if (result == "repeat_all" || result == "again") {
      widget.algProvider.reset(skippedAlgs: skippedAlgs);
    } else if (result == "repeat_target_time") {
      final prefs = await SharedPreferences.getInstance();
      final target = prefs.getDouble("target_time") ?? widget.targetTime;
      for (AlgTime algTime in timesCopy) {
        if (isUnderTargetTime(algTime.timeMs, target)) {
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
    if (c == CubeConnection.lost || c == CubeConnection.disconnected) {
      // The cube drives this screen; without it, drop back to the menu.
      Navigator.pop(context);
    }
  }

  void _onTimeRaceEnded() async {
    List<AlgTime> timesCopy = List.from(times);
    int totalTimeMs = _elapsedSessionMs();
    setState(() {
      isPressed = false;
      stopwatch.stop();
      stopwatch.reset();
      times.clear();
      nextAlgs.clear();
      timerStartTime = null;
    });

    final result = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => _buildSummary(timesCopy, totalTimeMs)));

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
    _cubeMode = mgr.isConnected && CubeRunController.supports(widget.algType);
    if (_cubeMode) {
      _cubeRun = CubeRunController(widget.algType);
      final cube = mgr.cube!;
      _stateSub = cube.states.listen(_onCubeState);
      _moveSub = cube.moves.listen((_) => _onCubeMove());
      mgr.connection.addListener(_onConnectionChanged);
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
    _stateSub?.cancel();
    _moveSub?.cancel();
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

  // In-run panel: the cube drives timing and advance, so screen taps are inert;
  // a Skip button is the only manual control.
  Widget _buildCubeRun(
      ThemeData theme, AppPalette p, double progress, String timerText) {
    final l10n = AppLocalizations.of(context)!;
    final phase = _cubeRun?.phase ?? CubePhase.recognition;
    final phaseLabel = phase == CubePhase.execution
        ? l10n.smartCubeExecution
        : l10n.smartCubeRecognition;
    return Column(
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: OutlinedButton.icon(
            onPressed: _skipCubeCase,
            icon: const Icon(Icons.skip_next),
            label: Text(l10n.smartCubeSkip),
          ),
        ),
      ],
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
