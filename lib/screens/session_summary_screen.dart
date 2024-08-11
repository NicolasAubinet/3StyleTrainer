import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../alg_structs.dart';
import '../utils.dart';

const double COLUMN_WIDTH_1 = 45;
const double COLUMN_WIDTH_2 = 110;
const double COLUMN_WIDTH_3 = 100;

class SessionSummaryScreen extends StatefulWidget {
  final List<AlgTime> algTimes;
  final double targetTime;

  const SessionSummaryScreen(
      {super.key, required this.algTimes, required this.targetTime});

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
        label: SizedBox(
          width: COLUMN_WIDTH_1,
          child: Text(
            "ID",
            style: theme.textTheme.titleMedium,
          ),
        ),
      ),
      DataColumn(
        onSort: onSort,
        label: SizedBox(
          width: COLUMN_WIDTH_2,
          child: Center(
            child: Text(
              "Alg",
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
      ),
      DataColumn(
        onSort: onSort,
        label: SizedBox(
          width: COLUMN_WIDTH_3,
          child: Text(
            "Time",
            style: theme.textTheme.titleMedium,
          ),
        ),
      ),
    ];
  }

  DataRow toDataRow(AlgTime algTime, ThemeData theme) {
    return DataRow(cells: [
      DataCell(SizedBox(
        width: COLUMN_WIDTH_1,
        child: Text(
          (algTime.index).toString(),
          style: theme.textTheme.displaySmall,
        ),
      )),
      DataCell(SizedBox(
        width: COLUMN_WIDTH_2,
        child: Center(
          child: Text(
            algTime.alg.name,
            style: theme.textTheme.displaySmall,
          ),
        ),
      )),
      DataCell(SizedBox(
        width: COLUMN_WIDTH_3,
        child: Text(
          timeToString(algTime.timeMs, fractionDigits: 2),
          style: theme.textTheme.displaySmall?.copyWith(
              color: isUnderTargetTime(algTime.timeMs, widget.targetTime)
                  ? Colors.green
                  : Colors.red),
        ),
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
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                      onPressed: () => _onRepeatTargetTimePressed(),
                      child: Text(AppLocalizations.of(context)!
                          .repeatTargetTime(widget.targetTime))),
                ],
              ),
              SizedBox(height: 8),
              ElevatedButton(
                  onPressed: () => {Navigator.pop(context, 'back')},
                  child: Text(AppLocalizations.of(context)!.back)),
              SizedBox(height: 3),
              Text(AppLocalizations.of(context)!.average(getFormatedAverage()),
                  style: theme.textTheme.displaySmall),
              SizedBox(height: 5),
              Expanded(
                child: Card(
                  color: Colors.black12,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: DataTable(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
