import 'dart:async' as async;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:timer_count_down/timer_count_down.dart';

import '../alg_provider.dart';
import '../alg_structs.dart';
import '../equalizing_selector.dart';
import '../practice_type.dart';
import '../theme/theme_scope.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
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

  void _onTapDown() {
    if (!isReady ||
        isPressed ||
        alg == null ||
        stopwatch.elapsedMilliseconds / 1000 < MINIMUM_ALLOWED_TIME) {
      return;
    }

    setState(() {
      isPressed = true;

      int elapsedMilliseconds = stopwatch.elapsedMilliseconds;
      times.add(AlgTime(times.length + 1, elapsedMilliseconds, alg!));

      stopwatch.stop();

      if (isRecordingRun(
        practiceType: widget.practiceType,
        algType: widget.algType,
        algsShownInAdvance: widget.algsShownInAdvance,
        recordTimes: widget.recordTimes,
      )) {
        String algName = alg!.name;
        DatabaseManager()
            .insertResult(widget.algType, algName, elapsedMilliseconds);
        // Keep the selector's weights fresh across a long "again" chain.
        final provider = widget.algProvider;
        if (provider is EqualizingSelector) {
          provider.recordSolve(algName);
        }
      }
    });
  }

  void _onTapUp() async {
    if (!isReady || alg == null || !isPressed) {
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
        if (widget.practiceType == PracticeType.sets) {
          // Sets completed, stop
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
              builder: (context) => SessionSummaryScreen(
                    algTimes: timesCopy,
                    targetTime: widget.targetTime,
                    practiceType: widget.practiceType,
                    totalTimeMs: totalTimeMs,
                  )));

      setState(() {
        isReady = false;
      });

      if (result == "repeat_all") {
        widget.algProvider.reset(skippedAlgs: skippedAlgs);
      } else if (result == "repeat_target_time") {
        for (AlgTime algTime in timesCopy) {
          if (isUnderTargetTime(algTime.timeMs, widget.targetTime)) {
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
            builder: (context) => SessionSummaryScreen(
                  algTimes: timesCopy,
                  targetTime: widget.targetTime,
                  practiceType: widget.practiceType,
                  totalTimeMs: totalTimeMs,
                )));

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
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (LogicalKeyboardKey.space == event.logicalKey) {
      if (event is KeyDownEvent) {
        _onTapDown();
      } else if (event is KeyUpEvent) {
        _onTapUp();
      }
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

  String _title(BuildContext context) {
    final typeName = widget.algType.getLocalizedName(context);
    return "$typeName · ${widget.practiceType.getLocalizedName(context)}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;

    var timerText = timeToString(stopwatch.elapsedMilliseconds);
    final progress = widget.practiceType == PracticeType.sets
        ? widget.algProvider
            .getProgression(preFetchedAlgsCount: nextAlgs.length)
        : getTimeRaceProgression();

    final Widget content = isReady
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

    return AppScaffold(title: _title(context), body: content);
  }
}
