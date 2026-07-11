import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../alg_structs.dart';
import '../database_manager.dart';
import '../l10n/app_localizations.dart';
import '../stats_date_range.dart';
import '../theme/app_palette.dart';
import '../theme/theme_scope.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/glass_panel.dart';
import '../widgets/sort_header.dart';
import 'alg_result_details_screen.dart';

enum _SortColumn { alg, recognition, execution, total }

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
    AlgType.TwoTwist,
    AlgType.Parity,
  ];

  static const String _sortColumnKey = "alg_times_sort_column";
  static const String _sortAscendingKey = "alg_times_sort_ascending";
  static const String _categoryKey = "alg_times_category";
  static const String _rangeKey = "alg_times_range";

  AlgType _category = AlgType.Corner;
  StatsDateRange _range = StatsDateRange.all;
  List<AlgStats> _stats = [];
  // Sort: by total (default, slowest first), recognition/execution split, or alg name.
  final SortState<_SortColumn> _sort = SortState(
      column: _SortColumn.total, direction: SortDirection.descending);
  // Gradient anchors over the shown averages: median = white (so ~half the
  // cases are green and half red), 10th/90th percentile = full green/red.
  double _loAvgMs = 0;
  double _medAvgMs = 0;
  double _hiAvgMs = 0;
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    final prefs = await SharedPreferences.getInstance();
    _sort.column = _readEnum(
        prefs.getString(_sortColumnKey), _SortColumn.values, _SortColumn.total);
    _sort.direction = (prefs.getBool(_sortAscendingKey) ?? false)
        ? SortDirection.ascending
        : SortDirection.descending;
    _category = _readEnum(prefs.getString(_categoryKey), _categories, _category);
    _range =
        _readEnum(prefs.getString(_rangeKey), StatsDateRange.values, _range);
    await _loadStats();
  }

  T _readEnum<T extends Enum>(String? name, List<T> values, T fallback) =>
      values.firstWhere((e) => e.name == name, orElse: () => fallback);

  Future<void> _loadStats() async {
    if (!mounted) return;
    int generation = ++_loadGeneration;
    setState(() => _loading = true);
    List<AlgStats> stats =
        await DatabaseManager().getAlgStats(_category, sinceMs: _range.cutoffMs());
    if (!mounted || generation != _loadGeneration) return;
    _applySort(stats);
    final avgs = stats.map((s) => s.avgMs).toList()..sort();
    setState(() {
      _stats = stats;
      _loAvgMs = _percentile(avgs, 0.10);
      _medAvgMs = _median(avgs);
      _hiAvgMs = _percentile(avgs, 0.90);
      _loading = false;
    });
  }

  void _applySort(List<AlgStats> stats) {
    stats.sort((a, b) {
      if (_sort.column == _SortColumn.alg) {
        final cmp = a.alg.compareTo(b.alg);
        return _sort.direction.isAscending ? cmp : -cmp;
      }
      // Cases with no split data (null) always sort last, either direction.
      final va = _sortValue(a), vb = _sortValue(b);
      if (va == null || vb == null) {
        if (va == vb) return 0;
        return va == null ? 1 : -1;
      }
      final cmp = va.compareTo(vb);
      return _sort.direction.isAscending ? cmp : -cmp;
    });
  }

  double? _sortValue(AlgStats s) {
    switch (_sort.column) {
      case _SortColumn.recognition:
        return s.avgRecognitionMs;
      case _SortColumn.execution:
        return s.avgExecutionMs;
      default:
        return s.avgMs;
    }
  }

  void _onSort(_SortColumn column) {
    setState(() {
      // alg -> A→Z, time columns -> slowest first.
      _sort.toggle(
          column,
          column == _SortColumn.alg
              ? SortDirection.ascending
              : SortDirection.descending);
      _applySort(_stats);
    });
    _persistSort();
  }

  void _persistSort() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_sortColumnKey, _sort.column.name);
    prefs.setBool(_sortAscendingKey, _sort.direction.isAscending);
  }

  void _persistFilters() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_categoryKey, _category.name);
    prefs.setString(_rangeKey, _range.name);
  }

  double _percentile(List<double> sortedAsc, double p) {
    if (sortedAsc.isEmpty) return 0;
    final idx = ((sortedAsc.length - 1) * p).round();
    return sortedAsc[idx];
  }

  double _median(List<double> sortedAsc) {
    if (sortedAsc.isEmpty) return 0;
    final m = sortedAsc.length ~/ 2;
    return sortedAsc.length.isOdd
        ? sortedAsc[m]
        : (sortedAsc[m - 1] + sortedAsc[m]) / 2;
  }

  // Green (fastest) -> white (median) -> red (slowest). White is anchored on
  // the median so about half the cases fall on each side; the 10th/90th
  // percentiles are the full green/red ends so outliers don't wash it out.
  Color _avgColor(double avgMs, AppPalette p) {
    if (_hiAvgMs <= _loAvgMs) return p.textPrimary;
    double t;
    if (avgMs <= _medAvgMs) {
      final span = _medAvgMs - _loAvgMs;
      t = span <= 0 ? 0.5 : 0.5 * ((avgMs - _loAvgMs) / span).clamp(0.0, 1.0);
    } else {
      final span = _hiAvgMs - _medAvgMs;
      final frac = span <= 0 ? 1.0 : ((avgMs - _medAvgMs) / span).clamp(0.0, 1.0);
      t = 0.5 + 0.5 * frac;
    }
    return t <= 0.5
        ? Color.lerp(p.good, p.textPrimary, t / 0.5)!
        : Color.lerp(p.textPrimary, p.bad, (t - 0.5) / 0.5)!;
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
    if (mounted) _loadStats();
  }

  Widget _filter<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final p = context.palette;
    return Expanded(
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w600,
                    color: p.textFaint)),
            SizedBox(
              height: 26,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: p.surfaceOpaque,
                  iconEnabledColor: p.textMuted,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary),
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Recognition/execution split subtitle, or an em dash when the case has no
  // smart-cube solves to split.
  Widget _splitLabel(AlgStats stats, AppPalette p) {
    final recog = stats.avgRecognitionMs, exec = stats.avgExecutionMs;
    if (recog == null || exec == null) {
      return Text("—", style: TextStyle(fontSize: 13, color: p.textFaint));
    }
    TextSpan part(String label, double ms) => TextSpan(children: [
          TextSpan(
              text: "$label ",
              style: TextStyle(fontSize: 11, color: p.textFaint)),
          TextSpan(
              text: timeToString(ms.round(), fractionDigits: 2),
              style: TextStyle(
                  fontFamily: MONO_FONT, fontSize: 13, color: p.textMuted)),
        ]);
    return Text.rich(TextSpan(children: [
      part("R", recog),
      const TextSpan(text: "   "),
      part("E", exec),
    ]));
  }

  Widget _statCard(AlgStats stats, AppPalette p, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        onTap: () => _openDetails(stats.alg),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(stats.alg,
                  style: TextStyle(
                      fontFamily: MONO_FONT,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary)),
            ),
            Expanded(child: _splitLabel(stats, p)),
            Text(
              timeToString(stats.avgMs.round(), fractionDigits: 2),
              style: TextStyle(
                  fontFamily: MONO_FONT,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: _avgColor(stats.avgMs, p)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final totalSolves = _stats.fold<int>(0, (sum, s) => sum + s.count);
    final totalTimeMs =
        _stats.fold<double>(0, (sum, s) => sum + s.avgMs * s.count);
    final globalAvgMs = totalSolves > 0 ? totalTimeMs / totalSolves : 0.0;

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_stats.isEmpty) {
      content = Center(
        child: Text(l10n.noRecordedTimes,
            style: TextStyle(fontSize: 16, color: p.textMuted)),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
            child: Row(
              children: [
                SortHeader(
                    label: l10n.columnAlg.toUpperCase(),
                    column: _SortColumn.alg,
                    state: _sort,
                    onSort: _onSort),
                const Spacer(),
                SortHeader(
                    label: l10n.columnRecognition.toUpperCase(),
                    column: _SortColumn.recognition,
                    state: _sort,
                    onSort: _onSort),
                SortHeader(
                    label: l10n.columnExecution.toUpperCase(),
                    column: _SortColumn.execution,
                    state: _sort,
                    onSort: _onSort),
                SortHeader(
                    label: l10n.columnTotal.toUpperCase(),
                    column: _SortColumn.total,
                    state: _sort,
                    onSort: _onSort),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _stats.length,
              itemBuilder: (context, i) => _statCard(_stats[i], p, l10n),
            ),
          ),
        ],
      );
    }

    return AppScaffold(
      title: l10n.algTimesTitle,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                l10n.totalSolves(totalSolves),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: p.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.globalAvg(timeToString(globalAvgMs.round(), fractionDigits: 2)),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w500, color: p.textFaint),
              ),
            ],
          ),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.fromLTRB(15, 6, 15, 6),
        child: Column(
          children: [
            Row(
              children: [
                _filter<AlgType>(
                  label: l10n.statsType,
                  value: _category,
                  items: _categories
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(t.getLocalizedName(context))))
                      .toList(),
                  onChanged: (t) {
                    if (t != null && t != _category) {
                      setState(() => _category = t);
                      _persistFilters();
                      _loadStats();
                    }
                  },
                ),
                const SizedBox(width: 12),
                _filter<StatsDateRange>(
                  label: l10n.statsPeriod,
                  value: _range,
                  items: StatsDateRange.values
                      .map((r) => DropdownMenuItem(
                          value: r, child: Text(r.getLocalizedName(context))))
                      .toList(),
                  onChanged: (r) {
                    if (r != null && r != _range) {
                      setState(() => _range = r);
                      _persistFilters();
                      _loadStats();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
