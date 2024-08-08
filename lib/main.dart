import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alg_provider.dart';
import 'custom_edges.dart';
import 'themes.dart';

const double DEFAULT_TARGET_TIME = 2.0;

AlgProvider getNewAlgProvider() {
  // return LetterPairProvider();
  return CustomProvider.fromFileContent(CustomEdges.TEST);
}

String timeToString(int timeMs) {
  double floatValue = timeMs / 1000;
  return floatValue.toStringAsFixed(1);
}

void main() {
  runApp(MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '3-Style Trainer',
      theme: mainTheme,
      home: MenuScreen(),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [
        Locale('en'), // English
      ],
    );
  }
}

class AlgTime {
  final int index;
  final int timeMs;
  final Alg alg;

  const AlgTime(this.index, this.timeMs, this.alg);
}

class MenuScreen extends StatefulWidget {
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  double _targetTime = DEFAULT_TARGET_TIME;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  void _loadPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _targetTime = prefs.getDouble("target_time") ?? DEFAULT_TARGET_TIME;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
              child: Text(AppLocalizations.of(context)!.corners),
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => TimerScreen(_targetTime)));
              }),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {},
            child: Text(AppLocalizations.of(context)!.edges),
          ),
          SizedBox(height: 50),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                AppLocalizations.of(context)!.targetTime,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Container(
                color: Colors.black26,
                padding: EdgeInsets.symmetric(horizontal: 5.0),
                width: 50,
                // height: 30,
                child: NumberInputField(
                  decimal: true,
                  onChanged: (value) async {
                    SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    var doubleValue = double.tryParse(value);
                    if (doubleValue != null) {
                      prefs.setDouble("target_time", doubleValue);
                    } else {
                      prefs.remove("target_time");
                    }
                  },
                  defaultValue: _targetTime.toString(),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

class NumberInputField extends StatelessWidget {
  final bool decimal;
  final bool signed;
  final Function(String)? onChanged;
  final String? defaultValue;
  final textController = TextEditingController();

  NumberInputField(
      {this.decimal = false,
      this.signed = false,
      this.onChanged,
      this.defaultValue});

  @override
  Widget build(BuildContext context) {
    textController.text = defaultValue ?? "";

    return TextFormField(
      style: Theme.of(context).textTheme.labelSmall,
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimal,
        signed: signed,
      ),
      onChanged: onChanged,
      controller: textController,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r"[0-9.]")),
        TextInputFormatter.withFunction((oldValue, newValue) {
          final text = newValue.text;
          if (text.isEmpty) {
            return newValue;
          } else if (decimal) {
            return double.tryParse(text) == null ? oldValue : newValue;
          } else {
            return int.tryParse(text) == null ? oldValue : newValue;
          }
        }),
      ],
    );
  }
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

class SessionSummaryScreen extends StatefulWidget {
  final List<AlgTime> algTimes;

  const SessionSummaryScreen({super.key, required this.algTimes});

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  bool _sortAscending = true;
  int _sortColumnIndex = 0;

  List<DataColumn> getColumns(BuildContext context) {
    final theme = Theme.of(context);

    return <DataColumn>[
      DataColumn(
        onSort: onSort,
        label: Expanded(
          child: Text(
            "ID",
            style: theme.textTheme.titleMedium,
          ),
        ),
      ),
      DataColumn(
        onSort: onSort,
        label: Expanded(
          child: Text(
            "Alg",
            style: theme.textTheme.titleMedium,
          ),
        ),
      ),
      DataColumn(
        onSort: onSort,
        label: Expanded(
          child: Text(
            "Time",
            style: theme.textTheme.titleMedium,
          ),
        ),
      ),
    ];
  }

  int compareInt(bool ascending, int value1, int value2) =>
      ascending ? value1.compareTo(value2) : value2.compareTo(value1);

  int compareString(bool ascending, String value1, String value2) =>
      ascending ? value1.compareTo(value2) : value2.compareTo(value1);

  void onSort(int columnIndex, bool ascending) {
    if (columnIndex == 0) {
      widget.algTimes
          .sort((e1, e2) => compareInt(ascending, e1.index, e2.index));
    } else if (columnIndex == 1) {
      widget.algTimes
          .sort((e1, e2) => compareString(ascending, e1.alg.name, e2.alg.name));
    } else if (columnIndex == 2) {
      widget.algTimes
          .sort((e1, e2) => compareInt(ascending, e1.timeMs, e2.timeMs));
    }

    setState(() {
      _sortAscending = ascending;
      _sortColumnIndex = columnIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.sessionSummary),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(5.0),
          child: Column(
            children: [
              ElevatedButton(
                  onPressed: () => {Navigator.pop(context, 'repeat_all')},
                  child: Text(AppLocalizations.of(context)!.repeatAll)),
              SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                      onPressed: () =>
                          {Navigator.pop(context, 'repeat_target_time')},
                      child:
                          Text(AppLocalizations.of(context)!.repeatTargetTime)),
                ],
              ),
              SizedBox(height: 5),
              ElevatedButton(
                  onPressed: () => {Navigator.pop(context, 'back')},
                  child: Text(AppLocalizations.of(context)!.back)),
              DataTable(
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                  columns: getColumns(context),
                  rows: widget.algTimes
                      .map((e) => DataRow(cells: [
                            DataCell(Text(
                              (e.index).toString(),
                              style: theme.textTheme.displaySmall,
                            )),
                            DataCell(Text(
                              e.alg.name,
                              style: theme.textTheme.displaySmall,
                            )),
                            DataCell(Text(
                              timeToString(e.timeMs),
                              style: theme.textTheme.displaySmall,
                            )),
                          ]))
                      .toList()),
            ],
          ),
        ),
      ),
    );
  }
}
