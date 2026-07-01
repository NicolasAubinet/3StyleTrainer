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
import 'alg_result_details_screen.dart';

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

  static const String _sortByAvgKey = "alg_times_sort_by_avg";
  static const String _sortAscendingKey = "alg_times_sort_ascending";

  AlgType _category = AlgType.Corner;
  StatsDateRange _range = StatsDateRange.all;
  List<AlgStats> _stats = [];
  // Sort: by average (default, slowest first) or by alg name.
  bool _sortByAvg = true;
  bool _sortAscending = false;
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
    _sortByAvg = prefs.getBool(_sortByAvgKey) ?? true;
    _sortAscending = prefs.getBool(_sortAscendingKey) ?? false;
    await _loadStats();
  }

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
      final cmp =
          _sortByAvg ? a.avgMs.compareTo(b.avgMs) : a.alg.compareTo(b.alg);
      return _sortAscending ? cmp : -cmp;
    });
  }

  void _onSort(bool byAvg) {
    setState(() {
      if (_sortByAvg == byAvg) {
        _sortAscending = !_sortAscending;
      } else {
        _sortByAvg = byAvg;
        _sortAscending = !byAvg; // alg -> A→Z, avg -> slowest first
      }
      _applySort(_stats);
    });
    _persistSort();
  }

  void _persistSort() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool(_sortByAvgKey, _sortByAvg);
    prefs.setBool(_sortAscendingKey, _sortAscending);
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
            Expanded(
              child: Text(
                l10n.statsSolvesRange(
                  stats.count,
                  timeToString(stats.maxMs, fractionDigits: 1),
                  timeToString(stats.minMs, fractionDigits: 1),
                ),
                style: TextStyle(fontSize: 12, color: p.textFaint),
              ),
            ),
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

  Widget _sortHeader(String label, bool byAvg, AppPalette p) {
    final active = _sortByAvg == byAvg;
    final arrow = active ? (_sortAscending ? " ↑" : " ↓") : "";
    return InkWell(
      onTap: () => _onSort(byAvg),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text("$label$arrow",
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: active ? p.accent : p.textMuted)),
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
                _sortHeader(l10n.columnAlg.toUpperCase(), false, p),
                const Spacer(),
                _sortHeader(l10n.columnAvg.toUpperCase(), true, p),
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
                          value: t, child: Text(_categoryName(t))))
                      .toList(),
                  onChanged: (t) {
                    if (t != null && t != _category) {
                      setState(() => _category = t);
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
