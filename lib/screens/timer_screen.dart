import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../alg_provider.dart';
import '../alg_structs.dart';
import '../custom_edges.dart';
import '../utils.dart';
import 'session_summary_screen.dart';

AlgProvider getNewAlgProvider() {
  // return LetterPairProvider();
  return CustomProvider.fromFileContent(CustomEdges.TEST);
}

class TimerScreen extends StatefulWidget {
  double targetTime;

  TimerScreen(this.targetTime);

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  AlgProvider algProvider = getNewAlgProvider();
  bool isPressed = false;
  var stopwatch = Stopwatch();
  var times = <AlgTime>[];
  var skippedAlgs = <String>[];
  Alg? alg;
  late Timer refreshTimer;

  void _onTapDown() {
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
    List<AlgTime> timesCopy = List.from(times);

    setState(() {
      do {
        alg = algProvider.getNextAlg();
      } while (alg != null && skippedAlgs.contains(alg!.name));

      isPressed = false;
      stopwatch.reset();
      if (alg == null) {
        algProvider = getNewAlgProvider();
        times.clear();
      } else {
        stopwatch.start();
      }
    });

    if (alg == null) {
      final result = await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => SessionSummaryScreen(algTimes: timesCopy)));
      if (result == "repeat_all") {
      } else if (result == "repeat_target_time") {
        bool allCasesBelowTarget = true;
        for (AlgTime algTime in timesCopy) {
          double execTime = algTime.timeMs / 1000;
          if (execTime < widget.targetTime) {
            skippedAlgs.add(algTime.alg.name);
          } else {
            allCasesBelowTarget = false;
          }
        }

        if (allCasesBelowTarget) {
          _sendAllCasesWereSubTargetMessage();
          back();
        }
      } else if (result == "back") {
        back();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    refreshTimer = Timer.periodic(
        Duration(milliseconds: 50), (Timer t) => setState(() {}));
  }

  @override
  void dispose() {
    super.dispose();
    refreshTimer.cancel();
  }

  void back() {
    Navigator.pop(context);
  }

  void _sendAllCasesWereSubTargetMessage() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context)!.allCasesWereSubTarget),
    ));
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
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _onTapDown(),
          onPointerUp: (_) => _onTapUp(),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  alg != null
                      ? alg!.name
                      : AppLocalizations.of(context)!.pressToStart,
                  style: theme.textTheme.displayLarge,
                ),
                Text(
                  timerText,
                  style: theme.textTheme.displaySmall,
                )
              ],
            ),
          ),
        ));
  }
}
