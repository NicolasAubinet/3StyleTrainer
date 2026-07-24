import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../alg_structs.dart';
import '../database_manager.dart';
import '../l10n/app_localizations.dart';
import '../stats_date_range.dart';
import '../theme/app_palette.dart';
import '../theme/theme_scope.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_segmented_control.dart';
import '../widgets/glass_panel.dart';
import '../widgets/sort_header.dart';
import 'alg_error_details_screen.dart';
import 'alg_result_details_screen.dart';

enum _SortColumn { alg, recognition, execution, total }

enum _ErrorSortColumn { alg, count }

enum _StatsView { times, errors }

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
  static const String _viewKey = "alg_stats_view";

  AlgType _category = AlgType.Corner;
  StatsDateRange _range = StatsDateRange.all;
  _StatsView _view = _StatsView.times;
  // The Times/Errors toggle only exists once a cube run has logged some error;
  // clearing the last one hides it again (and forces the view back to Times).
  bool _hasAnyErrors = false;

  List<AlgStats> _stats = [];
  List<AlgMistakeStats> _mistakeStats = [];
  final DateFormat _shortDateFormat = DateFormat('yyyy-MM-dd');

  // Sort: by total (default, slowest first), recognition/execution split, or alg name.
  final SortState<_SortColumn> _sort = SortState(
      column: _SortColumn.total, direction: SortDirection.descending);
  // Errors sort: by count (default, most-failed first) or alg name.
  final SortState<_ErrorSortColumn> _errorSort = SortState(
      column: _ErrorSortColumn.count, direction: SortDirection.descending);

  // Gradient anchors over the shown averages: median = white (so ~half the
  // cases are green and half red), 10th/90th percentile = full green/red.
  double _loAvgMs = 0;
  double _medAvgMs = 0;
  double _hiAvgMs = 0;
  bool _loading = true;
  int _loadGeneration = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _init() async {
    final prefs = await SharedPreferences.getInstance();
    // Read raw: an older build stored this key as an int, so getString would throw.
    final storedColumn = prefs.get(_sortColumnKey);
    _sort.column = _readEnum(storedColumn is String ? storedColumn : null,
        _SortColumn.values, _SortColumn.total);
    _sort.direction = (prefs.getBool(_sortAscendingKey) ?? false)
        ? SortDirection.ascending
        : SortDirection.descending;
    _category = _readEnum(prefs.getString(_categoryKey), _categories, _category);
    _range =
        _readEnum(prefs.getString(_rangeKey), StatsDateRange.values, _range);
    _view = _readEnum(prefs.getString(_viewKey), _StatsView.values, _view);
    _hasAnyErrors = await DatabaseManager().hasAnyMistakes();
    if (!_hasAnyErrors) _view = _StatsView.times;
    await _load();
  }

  // Re-check whether any error survives (across all types), and drop back to the
  // Times view if the toggle is about to disappear.
  Future<void> _refreshHasErrors() async {
    final has = await DatabaseManager().hasAnyMistakes();
    if (!mounted) return;
    setState(() {
      _hasAnyErrors = has;
      if (!has && _view == _StatsView.errors) _view = _StatsView.times;
    });
  }

  T _readEnum<T extends Enum>(String? name, List<T> values, T fallback) =>
      values.firstWhere((e) => e.name == name, orElse: () => fallback);

  Future<void> _load() =>
      _view == _StatsView.times ? _loadStats() : _loadMistakes();

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

  Future<void> _loadMistakes() async {
    if (!mounted) return;
    int generation = ++_loadGeneration;
    setState(() => _loading = true);
    List<AlgMistakeStats> stats = await DatabaseManager()
        .getAlgMistakeStats(_category, sinceMs: _range.cutoffMs());
    if (!mounted || generation != _loadGeneration) return;
    _applyErrorSort(stats);
    setState(() {
      _mistakeStats = stats;
      _loading = false;
    });
  }

  // The split columns only appear once the current view has smart-cube solves;
  // without them the screen looks exactly as it did before the split existed.
  bool get _hasSplits => _stats.any((s) => s.splitCount > 0);

  void _applySort(List<AlgStats> stats) {
    final hasSplits = stats.any((s) => s.splitCount > 0);
    stats.sort((a, b) {
      if (_sort.column == _SortColumn.alg) {
        final cmp = a.alg.compareTo(b.alg);
        return _sort.direction.isAscending ? cmp : -cmp;
      }
      // Cases with no split data (null) always sort last, either direction.
      final va = _sortValue(a, hasSplits), vb = _sortValue(b, hasSplits);
      if (va == null || vb == null) {
        if (va == vb) return 0;
        return va == null ? 1 : -1;
      }
      final cmp = va.compareTo(vb);
      return _sort.direction.isAscending ? cmp : -cmp;
    });
  }

  double? _sortValue(AlgStats s, bool hasSplits) {
    switch (_sort.column) {
      case _SortColumn.recognition:
        return hasSplits ? s.avgRecognitionMs : s.avgMs;
      case _SortColumn.execution:
        return hasSplits ? s.avgExecutionMs : s.avgMs;
      default:
        return s.avgMs;
    }
  }

  void _applyErrorSort(List<AlgMistakeStats> stats) {
    stats.sort((a, b) {
      final int cmp;
      if (_errorSort.column == _ErrorSortColumn.alg) {
        cmp = a.alg.compareTo(b.alg);
      } else {
        // Ties on count fall back to most-recent, so the freshest float up.
        cmp = a.count != b.count
            ? a.count.compareTo(b.count)
            : a.lastTimestamp.compareTo(b.lastTimestamp);
      }
      return _errorSort.direction.isAscending ? cmp : -cmp;
    });
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

  void _onErrorSort(_ErrorSortColumn column) {
    setState(() {
      // alg -> A→Z, count -> most-failed first.
      _errorSort.toggle(
          column,
          column == _ErrorSortColumn.alg
              ? SortDirection.ascending
              : SortDirection.descending);
      _applyErrorSort(_mistakeStats);
    });
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
    prefs.setString(_viewKey, _view.name);
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

  void _openErrorDetails(String alg) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlgErrorDetailsScreen(
          algType: _category,
          alg: alg,
          sinceMs: _range.cutoffMs(),
        ),
      ),
    );
    if (!mounted) return;
    await _refreshHasErrors();
    _load();
  }

  // "3 wrong · 1 requeued · 2 skipped" — only the kinds that actually occurred.
  String _kindBreakdown(AlgMistakeStats s, AppLocalizations l10n) {
    final parts = <String>[];
    final wrong = s.kindCounts[AlgMistakeKind.wrongCase] ?? 0;
    final requeued = s.kindCounts[AlgMistakeKind.requeued] ?? 0;
    final skipped = s.kindCounts[AlgMistakeKind.skipped] ?? 0;
    if (wrong > 0) parts.add(l10n.errorsBreakdownWrong(wrong));
    if (requeued > 0) parts.add(l10n.errorsBreakdownRequeued(requeued));
    if (skipped > 0) parts.add(l10n.errorsBreakdownSkipped(skipped));
    return parts.join(" · ");
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

  // Column widths shared by the header cells and the value cells so the numbers
  // line up under their labels. The header row is inset to match the card's
  // content box (GlassPanel: 14px padding + 1px border).
  static const double _algCellWidth = 46;
  static const double _splitCellWidth = 52;
  static const double _totalCellWidth = 62;
  static const double _cardContentInset = 15;

  // A right-aligned recognition/execution value under its header; a faint dash
  // when this case has no cube solves (only reachable in a split view).
  Widget _splitCell(double? ms, AppPalette p) {
    return SizedBox(
      width: _splitCellWidth,
      child: Text(
        ms == null ? "–" : timeToString(ms.round(), fractionDigits: 2),
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
            fontFamily: MONO_FONT,
            fontSize: 13,
            color: ms == null ? p.textFaint : p.textMuted),
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
              width: _algCellWidth,
              child: Text.rich(
                  algTextSpan(
                      stats.alg,
                      TextStyle(
                          fontFamily: MONO_FONT,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary)),
                  maxLines: 1),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.statsSolvesCount(stats.count),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.textFaint),
                  ),
                  Text(
                    l10n.statsSpread(
                      timeToString(stats.minMs, fractionDigits: 1),
                      timeToString(stats.maxMs, fractionDigits: 1),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.textFaint),
                  ),
                ],
              ),
            ),
            if (_hasSplits) ...[
              _splitCell(stats.avgRecognitionMs, p),
              _splitCell(stats.avgExecutionMs, p),
              const SizedBox(width: 8),
            ],
            SizedBox(
              width: _totalCellWidth,
              child: Text(
                timeToString(stats.avgMs.round(), fractionDigits: 2),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                    fontFamily: MONO_FONT,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: _avgColor(stats.avgMs, p)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(AlgMistakeStats stats, AppPalette p, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        onTap: () => _openErrorDetails(stats.alg),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: _algCellWidth,
              child: Text.rich(
                  algTextSpan(
                      stats.alg,
                      TextStyle(
                          fontFamily: MONO_FONT,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary)),
                  maxLines: 1),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _kindBreakdown(stats, l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.textFaint),
                  ),
                  Text(
                    l10n.errorsLastSeen(_shortDateFormat.format(
                        DateTime.fromMillisecondsSinceEpoch(
                            stats.lastTimestamp))),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.textFaint),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _totalCellWidth,
              child: Text(
                stats.count.toString(),
                textAlign: TextAlign.right,
                maxLines: 1,
                style: TextStyle(
                    fontFamily: MONO_FONT,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: p.bad),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(AppPalette p, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 48, color: p.textFaint),
            const SizedBox(height: 16),
            Text(l10n.noRecordedTimes,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: p.textMuted)),
            const SizedBox(height: 8),
            Text(
              l10n.noRecordedTimesHint(
                  l10n.practiceTypeTimeRaceShort, l10n.recordTimes),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: p.textFaint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorsEmptyState(AppPalette p, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: p.textFaint),
            const SizedBox(height: 16),
            Text(l10n.noRecordedErrors,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: p.textMuted)),
            const SizedBox(height: 8),
            Text(
              l10n.noRecordedErrorsHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: p.textFaint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timesContent(AppPalette p, AppLocalizations l10n) {
    if (_stats.isEmpty) return _emptyState(p, l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              _cardContentInset, 0, _cardContentInset, 2),
          child: Row(
            children: [
              SortHeader(
                  label: l10n.columnAlg.toUpperCase(),
                  column: _SortColumn.alg,
                  state: _sort,
                  onSort: _onSort,
                  width: _algCellWidth),
              const Spacer(),
              if (_hasSplits) ...[
                SortHeader(
                    label: l10n.columnRecognition.toUpperCase(),
                    column: _SortColumn.recognition,
                    state: _sort,
                    onSort: _onSort,
                    width: _splitCellWidth,
                    align: TextAlign.right),
                SortHeader(
                    label: l10n.columnExecution.toUpperCase(),
                    column: _SortColumn.execution,
                    state: _sort,
                    onSort: _onSort,
                    width: _splitCellWidth,
                    align: TextAlign.right),
                const SizedBox(width: 8),
              ],
              SortHeader(
                  label: (_hasSplits ? l10n.columnTotal : l10n.columnAvg)
                      .toUpperCase(),
                  column: _SortColumn.total,
                  state: _sort,
                  onSort: _onSort,
                  width: _totalCellWidth,
                  align: TextAlign.right),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _stats.length,
              itemBuilder: (context, i) => _statCard(_stats[i], p, l10n),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorsContent(AppPalette p, AppLocalizations l10n) {
    if (_mistakeStats.isEmpty) return _errorsEmptyState(p, l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              _cardContentInset, 0, _cardContentInset, 2),
          child: Row(
            children: [
              SortHeader(
                  label: l10n.columnAlg.toUpperCase(),
                  column: _ErrorSortColumn.alg,
                  state: _errorSort,
                  onSort: _onErrorSort,
                  width: _algCellWidth),
              const Spacer(),
              SortHeader(
                  label: l10n.columnErrorCount.toUpperCase(),
                  column: _ErrorSortColumn.count,
                  state: _errorSort,
                  onSort: _onErrorSort,
                  width: _totalCellWidth,
                  align: TextAlign.right),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _mistakeStats.length,
              itemBuilder: (context, i) => _errorCard(_mistakeStats[i], p, l10n),
            ),
          ),
        ),
      ],
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
    final totalErrors = _mistakeStats.fold<int>(0, (sum, s) => sum + s.count);
    final isErrors = _view == _StatsView.errors;

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (isErrors) {
      content = _errorsContent(p, l10n);
    } else {
      content = _timesContent(p, l10n);
    }

    return AppScaffold(
      title: l10n.algStatsTitle,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: isErrors
                ? [
                    Text(
                      l10n.totalErrors(totalErrors),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: p.textMuted),
                    ),
                  ]
                : [
                    Text(
                      l10n.totalSolves(totalSolves),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: p.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.globalAvg(
                          timeToString(globalAvgMs.round(), fractionDigits: 2)),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: p.textFaint),
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
                      _load();
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
                      _load();
                    }
                  },
                ),
              ],
            ),
            if (_hasAnyErrors) ...[
              const SizedBox(height: 10),
              AppSegmentedControl<_StatsView>(
                selected: _view,
                dense: true,
                options: [
                  SegmentOption(_StatsView.times, l10n.statsViewTimes),
                  SegmentOption(_StatsView.errors, l10n.statsViewErrors),
                ],
                onChanged: (v) {
                  if (v == _view) return;
                  setState(() => _view = v);
                  _persistFilters();
                  _load();
                },
              ),
            ],
            const SizedBox(height: 12),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
