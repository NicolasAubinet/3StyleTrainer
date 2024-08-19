import 'dart:async' as async;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:timer_count_down/timer_count_down.dart';

import '../alg_provider.dart';
import '../alg_structs.dart';
import '../practice_type.dart';
import '../utils.dart';
import 'session_summary_screen.dart';

const double MINIMUM_ALLOWED_TIME = 0.30; // to prevent misclick via double tap
const int TIME_RACE_DURATION_SECONDS = 60;

class TimerScreen extends StatefulWidget {
  final PracticeType practiceType;
  final double targetTime;
  final AlgProvider algProvider;
  final AlgType algType;
  final List<String> skippedAlgs;

  TimerScreen(
      this.practiceType, this.targetTime, this.algProvider, this.algType,
      {this.skippedAlgs = const []});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  bool isPressed = false;
  var stopwatch = Stopwatch();
  var times = <AlgTime>[];
  var skippedAlgs = <String>[];
  Alg? alg;
  late async.Timer refreshTimer;
  DateTime? timerStartTime;
  bool isReady = false;

  void _onTapDown() {
    if (!isReady ||
        alg == null ||
        stopwatch.elapsedMilliseconds / 1000 < MINIMUM_ALLOWED_TIME) {
      return;
    }

    setState(() {
      isPressed = true;

      int elapsedMilliseconds = stopwatch.elapsedMilliseconds;
      times.add(AlgTime(times.length + 1, elapsedMilliseconds, alg!));

      stopwatch.stop();

      if (widget.practiceType == PracticeType.timeRace) {
        skippedAlgs.add(alg!.name);
        DatabaseManager().insertExecutedTimeRaceAlg(widget.algType, alg!.name);
      }
    });
  }

  void _onTapUp() async {
    if (!isReady || alg == null || !isPressed) {
      return;
    }

    List<AlgTime> timesCopy = List.from(times);

    setState(() {
      _fetchNextAlg();
      isPressed = false;
      stopwatch.reset();
      if (alg == null) {
        times.clear();
        timerStartTime = null;

        if (widget.practiceType == PracticeType.timeRace) {
          DatabaseManager().resetExecutedTimeRaceAlgs();
          widget.algProvider.reset(); // reset to all algs
          _fetchNextAlg();
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
                  )));

      setState(() {
        isReady = false;
      });

      if (result == "repeat_all") {
        widget.algProvider.reset();
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
    do {
      alg = widget.algProvider.getNextAlg();
    } while (alg != null && skippedAlgs.contains(alg!.name));
    return alg;
  }

  void _onTimeRaceEnded() async {
    List<AlgTime> timesCopy = List.from(times);
    setState(() {
      stopwatch.stop();
      stopwatch.reset();
      times.clear();
      timerStartTime = null;
    });

    final result = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => SessionSummaryScreen(
                  algTimes: timesCopy,
                  targetTime: widget.targetTime,
                  practiceType: widget.practiceType,
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

  TextSpan getAlgTextSpan(ThemeData theme, String algChar) {
    Set<String> greenCharacters = {'é', 'É'};
    Set<String> redCharacters = {'è', 'È'};

    if (greenCharacters.contains(algChar)) {
      return TextSpan(
        text: algChar,
        style: theme.textTheme.displayLarge!.copyWith(color: Colors.green),
      );
    } else if (redCharacters.contains(algChar)) {
      return TextSpan(
        text: algChar,
        style: theme.textTheme.displayLarge!.copyWith(color: Colors.orange),
      );
    } else {
      return TextSpan(
        text: algChar,
        style: theme.textTheme.displayLarge,
      );
    }
  }

  double getTimeRaceProgression() {
    if (timerStartTime == null) {
      return 0;
    }
    Duration duration = DateTime.now().difference(timerStartTime!);
    int ms = duration.inMilliseconds;
    double progression = ms / TIME_RACE_DURATION_SECONDS / 1000;
    return progression;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    var timerText = timeToString(stopwatch.elapsedMilliseconds);

    return Scaffold(
      backgroundColor:
          isPressed ? theme.colorScheme.secondary : theme.colorScheme.primary,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.timer),
      ),
      body: isReady
          ? Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _onTapDown(),
              onPointerUp: (_) => _onTapUp(),
              child: Column(
                children: [
                  Container(
                    height: 12.0,
                    padding: EdgeInsets.all(1.5),
                    color: Colors.white,
                    child: Align(
                      alignment: Alignment.center,
                      child: LinearProgressIndicator(
                        value: widget.practiceType == PracticeType.sets
                            ? widget.algProvider.getProgression()
                            : getTimeRaceProgression(),
                        minHeight: 10,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: (alg != null ? alg!.name : "--")
                                .characters
                                .map((e) => getAlgTextSpan(theme, e))
                                .toList(),
                          ),
                        ),
                        Text(
                          timerText,
                          style: theme.textTheme.displaySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : Center(
              child: Countdown(
                seconds: 3,
                build: (BuildContext context, double time) => Text(
                  time.ceil() > 0 ? time.ceil().toString() : "",
                  style: theme.textTheme.displayLarge,
                ),
                interval: Duration(milliseconds: 100),
                onFinished: () {
                  setState(() {
                    isReady = true;
                    timerStartTime = DateTime.now();
                    _fetchNextAlg();
                    stopwatch.start();
                  });
                },
              ),
            ),
    );
  }
}
