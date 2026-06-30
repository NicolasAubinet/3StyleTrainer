import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../alg_structs.dart';
import '../database_manager.dart';
import '../l10n/app_localizations.dart';
import '../stats_date_range.dart';
import '../utils.dart';
import 'alg_result_details_screen.dart';

// Column indices for sorting / persisted sort state.
const int _colAlg = 0;
const int _colCount = 1;
const int _colMin = 2;
const int _colMax = 3;
const int _colAvg = 4;

const String _sortColumnKey = "alg_times_sort_column";
const String _sortAscendingKey = "alg_times_sort_ascending";

class AlgTimesScreen extends StatefulWidget {
  const AlgTimesScreen({super.key});

  @override
  State<AlgTimesScreen> createState() => _AlgTimesScreenState();
}

class _AlgTimesScreenState extends State<AlgTimesScreen> {
  static const List<AlgType> _categories = [
    AlgType.Corner,
    AlgType.Edge,
    AlgType.TwoFlip,
  ];

  AlgType _category = AlgType.Corner;
  StatsDateRange _range = StatsDateRange.all;
  List<AlgStats> _stats = [];
  bool _loading = true;
  int _loadGeneration = 0;

  // Default: worst (highest average) first.
  int _sortColumnIndex = _colAvg;
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int storedColumn = prefs.getInt(_sortColumnKey) ?? _colAvg;
    _sortColumnIndex =
        (storedColumn >= _colAlg && storedColumn <= _colAvg) ? storedColumn : _colAvg;
    _sortAscending = prefs.getBool(_sortAscendingKey) ?? false;
    await _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    // Ignore responses from superseded loads (rapid Type/Period switches).
    int generation = ++_loadGeneration;
    setState(() => _loading = true);
    List<AlgStats> stats =
        await DatabaseManager().getAlgStats(_category, sinceMs: _range.cutoffMs());
    if (!mounted || generation != _loadGeneration) return;
    _applySort(stats, _sortColumnIndex, _sortAscending);
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  int _compareInt(bool ascending, int a, int b) =>
      ascending ? a.compareTo(b) : b.compareTo(a);

  int _compareDouble(bool ascending, double a, double b) =>
      ascending ? a.compareTo(b) : b.compareTo(a);

  int _compareString(bool ascending, String a, String b) =>
      ascending ? a.compareTo(b) : b.compareTo(a);

  void _applySort(List<AlgStats> stats, int columnIndex, bool ascending) {
    switch (columnIndex) {
      case _colAlg:
        stats.sort((a, b) => _compareString(ascending, a.alg, b.alg));
      case _colCount:
        stats.sort((a, b) => _compareInt(ascending, a.count, b.count));
      case _colMin:
        stats.sort((a, b) => _compareInt(ascending, a.minMs, b.minMs));
      case _colMax:
        stats.sort((a, b) => _compareInt(ascending, a.maxMs, b.maxMs));
      case _colAvg:
        stats.sort((a, b) => _compareDouble(ascending, a.avgMs, b.avgMs));
    }
  }

  void _onSort(int columnIndex, bool ascending) async {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _applySort(_stats, columnIndex, ascending);
    });
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt(_sortColumnKey, columnIndex);
    prefs.setBool(_sortAscendingKey, ascending);
  }

  String _categoryName(AlgType type) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case AlgType.Corner:
        return l10n.corners;
      case AlgType.Edge:
        return l10n.edges;
      case AlgType.TwoFlip:
        return l10n.flips;
      case AlgType.Custom:
        return l10n.custom;
    }
  }

  Widget _buildCategoryDropdown(ThemeData theme) {
    return DropdownMenu<AlgType>(
      initialSelection: _category,
      label: Text(AppLocalizations.of(context)!.statsType,
          style: theme.textTheme.labelSmall),
      textStyle: theme.textTheme.labelSmall,
      onSelected: (AlgType? type) {
        if (type != null && type != _category) {
          setState(() => _category = type);
          _loadStats();
        }
      },
      dropdownMenuEntries: _categories
          .map((type) => DropdownMenuEntry<AlgType>(
                value: type,
                label: _categoryName(type),
                style: MenuItemButton.styleFrom(
                    textStyle: theme.textTheme.labelSmall),
              ))
          .toList(),
    );
  }

  Widget _buildRangeDropdown(ThemeData theme) {
    return DropdownMenu<StatsDateRange>(
      initialSelection: _range,
      label: Text(AppLocalizations.of(context)!.statsPeriod,
          style: theme.textTheme.labelSmall),
      textStyle: theme.textTheme.labelSmall,
      onSelected: (StatsDateRange? range) {
        if (range != null && range != _range) {
          setState(() => _range = range);
          _loadStats();
        }
      },
      dropdownMenuEntries: StatsDateRange.values
          .map((range) => DropdownMenuEntry<StatsDateRange>(
                value: range,
                label: range.getLocalizedName(context),
                style: MenuItemButton.styleFrom(
                    textStyle: theme.textTheme.labelSmall),
              ))
          .toList(),
    );
  }

  DataColumn _column(ThemeData theme, String label,
      {bool numeric = false, ColumnSize size = ColumnSize.M}) {
    return DataColumn2(
      numeric: numeric,
      size: size,
      onSort: _onSort,
      label: Text(label, style: theme.textTheme.labelLarge),
    );
  }

  void _openDetails(String alg) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlgResultDetailsScreen(
          algType: _category,
          alg: alg,
          sinceMs: _range.cutoffMs(),
        ),
      ),
    );
    // Times may have been deleted; refresh the aggregates.
    if (mounted) _loadStats();
  }

  DataRow _row(ThemeData theme, AlgStats stats) {
    final cellStyle = theme.textTheme.labelMedium;
    return DataRow(cells: [
      DataCell(Text(stats.alg, style: cellStyle)),
      DataCell(Text(stats.count.toString(), style: cellStyle)),
      DataCell(Text(timeToString(stats.minMs, fractionDigits: 2), style: cellStyle)),
      DataCell(Text(timeToString(stats.maxMs, fractionDigits: 2), style: cellStyle)),
      DataCell(Text(timeToString(stats.avgMs.round(), fractionDigits: 2),
          style: cellStyle)),
    ], onSelectChanged: (_) => _openDetails(stats.alg));
  }

  Widget _buildTable(ThemeData theme) {
    return DataTable2(
      fixedTopRows: 1,
      horizontalMargin: 10,
      columnSpacing: 5,
      showCheckboxColumn: false,
      sortColumnIndex: _sortColumnIndex,
      sortAscending: _sortAscending,
      columns: [
        _column(theme, "Alg", size: ColumnSize.S),
        _column(theme, "Count", numeric: true),
        _column(theme, "Min", numeric: true),
        _column(theme, "Max", numeric: true),
        _column(theme, "Avg", numeric: true),
      ],
      rows: _stats.map((stats) => _row(theme, stats)).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content;
    if (_loading) {
      content = Center(child: CircularProgressIndicator());
    } else if (_stats.isEmpty) {
      content = Center(
        child: Text(AppLocalizations.of(context)!.noRecordedTimes,
            style: theme.textTheme.labelLarge),
      );
    } else {
      content = Card(color: Colors.black12, child: _buildTable(theme));
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.algTimesTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCategoryDropdown(theme),
                _buildRangeDropdown(theme),
              ],
            ),
            SizedBox(height: 10),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
