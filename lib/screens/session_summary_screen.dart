import 'dart:async';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:three_style_trainer/practice_type.dart';

import '../alg_structs.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_scope.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';

const int BUTTON_PRESS_DELAY_MS = 250;

ButtonStyle summaryButtonStyle(ThemeData theme) => ElevatedButton.styleFrom(
      backgroundColor: theme.colorScheme.primary,
      foregroundColor: theme.colorScheme.onPrimary,
      elevation: 3,
    );

class SessionSummaryScreen extends StatefulWidget {
  final List<AlgTime> algTimes;
  final double targetTime;
  final PracticeType practiceType;
  final int totalTimeMs;

  const SessionSummaryScreen(
      {super.key,
      required this.algTimes,
      required this.targetTime,
      required this.practiceType,
      required this.totalTimeMs});

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  bool _sortAscending = true;
  int _sortColumnIndex = 0;
  bool _canPressButtons = false;
  late Timer _buttonsActivationTimer;

  @override
  void initState() {
    super.initState();

    _buttonsActivationTimer = Timer(
        Duration(milliseconds: BUTTON_PRESS_DELAY_MS),
        () => setState(() {
              _canPressButtons = true;
            }));
  }

  @override
  void dispose() {
    super.dispose();
    _buttonsActivationTimer.cancel();
  }

  List<DataColumn> getColumns(BuildContext context) {
    final theme = Theme.of(context);

    return <DataColumn>[
      DataColumn(
        onSort: onSort,
        label: Text(
          "ID",
          style: theme.textTheme.titleMedium,
        ),
      ),
      DataColumn(
        onSort: onSort,
        label: Text(
          "Alg",
          style: theme.textTheme.titleMedium,
        ),
      ),
      DataColumn(
        onSort: onSort,
        label: Text(
          "Time",
          style: theme.textTheme.titleMedium,
        ),
      ),
    ];
  }

  Color getAlgTimeColor(int timeMs, ThemeData theme) {
    if (widget.practiceType == PracticeType.sets) {
      return isUnderTargetTime(timeMs, widget.targetTime)
          ? Colors.green
          : Colors.red;
    } else {
      return theme.colorScheme.onSurface;
    }
  }

  DataRow toDataRow(AlgTime algTime, ThemeData theme) {
    return DataRow(cells: [
      DataCell(Text(
        (algTime.index).toString(),
        style: theme.textTheme.displaySmall,
      )),
      DataCell(Text(
        algTime.alg.name,
        style: theme.textTheme.displaySmall,
      )),
      DataCell(Text(
        timeToString(algTime.timeMs, fractionDigits: 2),
        style: theme.textTheme.displaySmall
            ?.copyWith(color: getAlgTimeColor(algTime.timeMs, theme)),
      )),
    ]);
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

  String getFormatedAverage() {
    if (widget.algTimes.isEmpty) {
      return "";
    }

    int totalTime = 0;
    for (AlgTime algTime in widget.algTimes) {
      totalTime += algTime.timeMs;
    }
    int averageTimeMs = (totalTime / widget.algTimes.length).round();
    return timeToString(averageTimeMs, fractionDigits: 2);
  }

  void _onRepeatTargetTimePressed() {
    bool allCasesBelowTarget = true;
    for (AlgTime algTime in widget.algTimes) {
      if (!isUnderTargetTime(algTime.timeMs, widget.targetTime)) {
        allCasesBelowTarget = false;
        break;
      }
    }

    if (allCasesBelowTarget) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!
            .allCasesWereSubTarget(widget.targetTime)),
      ));
    } else {
      Navigator.pop(context, 'repeat_target_time');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;

    return AppScaffold(
      title: AppLocalizations.of(context)!.sessionSummary,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Text(
              AppLocalizations.of(context)!
                  .totalTime(totalTimeToString(widget.totalTimeMs)),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.textMuted),
            ),
          ),
        ),
      ],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
          child: Column(
            children: [
              widget.practiceType == PracticeType.sets
                  ? SetsPracticeButtons(widget.targetTime,
                      () => _onRepeatTargetTimePressed(), _canPressButtons)
                  : TimeRaceStatsWidget(widget.algTimes.length),
              Text(AppLocalizations.of(context)!.average(getFormatedAverage()),
                  style: theme.textTheme.displaySmall),
              widget.practiceType == PracticeType.timeRace
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ElevatedButton(
                          style: summaryButtonStyle(theme),
                          onPressed: () => _canPressButtons
                              ? {Navigator.pop(context, 'again')}
                              : null,
                          child: Text(AppLocalizations.of(context)!.again)),
                    )
                  : Container(),
              SizedBox(height: 6),
              Expanded(
                child: Card(
                  color: p.panel,
                  child: DataTable2(
                      fixedTopRows: 1,
                      horizontalMargin: 10,
                      columnSpacing: 5,
                      sortColumnIndex: _sortColumnIndex,
                      sortAscending: _sortAscending,
                      columns: getColumns(context),
                      rows: widget.algTimes
                          .map((algTime) => toDataRow(algTime, theme))
                          .toList()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SetsPracticeButtons extends StatelessWidget {
  final double _targetTime;
  final Function _onPressed;
  final bool _canPress;

  SetsPracticeButtons(this._targetTime, this._onPressed, this._canPress);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        ElevatedButton(
            style: summaryButtonStyle(theme),
            onPressed: () =>
                _canPress ? {Navigator.pop(context, 'repeat_all')} : null,
            child: Text(AppLocalizations.of(context)!.repeatAll)),
        SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
                style: summaryButtonStyle(theme),
                onPressed: () => _canPress ? _onPressed() : null,
                child: Text(AppLocalizations.of(context)!
                    .repeatTargetTime(_targetTime))),
          ],
        ),
        SizedBox(height: 6),
      ],
    );
  }
}

class TimeRaceStatsWidget extends StatelessWidget {
  final int _completedAlgs;

  TimeRaceStatsWidget(this._completedAlgs);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppLocalizations.of(context)!.completedAlgs,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          Text(
            _completedAlgs.toString(),
            style: Theme.of(context).textTheme.displaySmall,
          )
        ],
      ),
      SizedBox(height: 5),
    ]);
  }
}
