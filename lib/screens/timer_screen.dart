import 'dart:async' as async;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:timer_count_down/timer_count_down.dart';

import '../alg_provider.dart';
import '../alg_structs.dart';
import '../utils.dart';
import 'session_summary_screen.dart';

const double MINIMUM_ALLOWED_TIME = 0.30; // to prevent misclick via double tap

class TimerScreen extends StatefulWidget {
  final double targetTime;
  final AlgProvider algProvider;

  TimerScreen(this.targetTime, this.algProvider);

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
  bool isReady = false;

  void _onTapDown() {
    if (!isReady ||
        alg == null ||
        stopwatch.elapsedMilliseconds / 1000 < MINIMUM_ALLOWED_TIME) {
      return;
    }

    setState(() {
      isPressed = true;

      var elapsedMilliseconds = stopwatch.elapsedMilliseconds;
      if (alg != null) {
        times.add(AlgTime(times.length + 1, elapsedMilliseconds, alg!));
      }

      stopwatch.stop();
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
        Navigator.pop(context);
      }
    }
  }

  Alg? _fetchNextAlg() {
    do {
      alg = widget.algProvider.getNextAlg();
    } while (alg != null && skippedAlgs.contains(alg!.name));
    return alg;
  }

  @override
  void initState() {
    super.initState();
    refreshTimer = async.Timer.periodic(
        Duration(milliseconds: 50), (async.Timer t) => setState(() {}));
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
                        value: widget.algProvider.getProgression(),
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
                    _fetchNextAlg();
                    stopwatch.start();
                  });
                },
              ),
            ),
    );
  }
}
