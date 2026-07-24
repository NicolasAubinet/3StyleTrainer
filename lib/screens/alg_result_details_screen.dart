import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../alg_structs.dart';
import '../database_manager.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_scope.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/glass_panel.dart';
import '../widgets/sort_header.dart';
import '../widgets/swipeable_row.dart';

enum _SortColumn { dateTime, recognition, execution, total }

// Lists every recorded attempt for one (algType, alg)
class AlgResultDetailsScreen extends StatefulWidget {
  final AlgType algType;
  final String alg;
  final int? sinceMs;

  const AlgResultDetailsScreen({
    super.key,
    required this.algType,
    required this.alg,
    this.sinceMs,
  });

  @override
  State<AlgResultDetailsScreen> createState() => _AlgResultDetailsScreenState();
}

class _AlgResultDetailsScreenState extends State<AlgResultDetailsScreen> {
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  final DateFormat _timeFormat = DateFormat('HH:mm:ss');

  List<AlgResult> _results = [];
  bool _loading = true;
  // Sort: by solve time or by date/time (default). Not persisted.
  final SortState<_SortColumn> _sort = SortState(
      column: _SortColumn.dateTime, direction: SortDirection.descending);
  final ValueNotifier<Object?> _openRow = ValueNotifier<Object?>(null);

  // The split columns only appear once this case has smart-cube attempts.
  bool get _hasSplits => _results.any((r) => r.recognitionMs != null);

  int? _sortValue(AlgResult r, bool hasSplits) {
    switch (_sort.column) {
      case _SortColumn.recognition:
        return hasSplits ? r.recognitionMs : r.resultMs;
      case _SortColumn.execution:
        return hasSplits ? r.executionMs : r.resultMs;
      case _SortColumn.total:
        return r.resultMs;
      case _SortColumn.dateTime:
        return r.timestamp;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _openRow.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<AlgResult> results = await DatabaseManager()
        .getAlgResults(widget.algType, widget.alg, sinceMs: widget.sinceMs);
    if (!mounted) return;
    _applySort(results);
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  void _applySort(List<AlgResult> results) {
    final hasSplits = results.any((r) => r.recognitionMs != null);
    results.sort((a, b) {
      // Attempts with no split (null) always sort last, either direction.
      final va = _sortValue(a, hasSplits), vb = _sortValue(b, hasSplits);
      if (va == null || vb == null) {
        if (va == vb) return 0;
        return va == null ? 1 : -1;
      }
      final cmp = va.compareTo(vb);
      return _sort.direction.isAscending ? cmp : -cmp;
    });
  }

  void _onSort(_SortColumn column) {
    setState(() {
      // Both columns start descending: newest first / slowest first.
      _sort.toggle(column, SortDirection.descending);
      _applySort(_results);
    });
  }

  // Delete by content (not id) so an undo re-insert round-trips cleanly without
  // the row's id going stale (see deleteRecordedResult / insertResult).
  void _deleteRow(AlgResult result) {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _results.removeWhere((r) => r.id == result.id);
      _openRow.value = null;
    });
    DatabaseManager().deleteRecordedResult(
        widget.algType, widget.alg, result.resultMs, result.timestamp);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text.rich(algTextSpan(
            l10n.deletedTime(
                widget.alg, timeToString(result.resultMs, fractionDigits: 2)),
            const TextStyle())),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () {
            DatabaseManager().insertResult(
                widget.algType, widget.alg, result.resultMs,
                timestamp: result.timestamp,
                recognitionMs: result.recognitionMs);
            setState(() {
              _results.add(result);
              _applySort(_results);
            });
          },
        ),
      ));
  }

  // Keep these widths in sync between the header and the rows so columns align.
  static const double _timeColumnWidth = 58;
  static const double _splitColumnWidth = 44;
  // Gap between the split columns and the total.
  static const double _splitGap = 6;

  Widget _sortHeader(String label, _SortColumn column,
          {double? width, TextAlign align = TextAlign.left}) =>
      SortHeader(
          label: label.toUpperCase(),
          column: column,
          state: _sort,
          onSort: _onSort,
          width: width,
          align: align);

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      // Row padding (16) so headers sit over their values.
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Expanded(child: _sortHeader(l10n.columnDateTime, _SortColumn.dateTime)),
          if (_hasSplits) ...[
            _sortHeader(l10n.columnRecognition, _SortColumn.recognition,
                width: _splitColumnWidth, align: TextAlign.right),
            _sortHeader(l10n.columnExecution, _SortColumn.execution,
                width: _splitColumnWidth, align: TextAlign.right),
            const SizedBox(width: _splitGap),
          ],
          _sortHeader(_hasSplits ? l10n.columnTotal : l10n.columnResult,
              _SortColumn.total,
              width: _timeColumnWidth, align: TextAlign.right),
        ],
      ),
    );
  }

  // A right-aligned recognition/execution value beside the total; a faint dash
  // for a press-timed attempt within a split view.
  Widget _splitCell(ThemeData theme, int? ms) {
    return SizedBox(
      width: _splitColumnWidth,
      child: Text(
        ms == null ? "–" : timeToString(ms, fractionDigits: 2),
        textAlign: TextAlign.right,
        maxLines: 1,
        style: theme.textTheme.labelLarge?.copyWith(
            color: ms == null
                ? context.palette.textFaint
                : context.palette.textMuted),
      ),
    );
  }

  Widget _buildRow(ThemeData theme, AlgResult result, bool peekHint) {
    final date = DateTime.fromMillisecondsSinceEpoch(result.timestamp);
    final p = context.palette;
    final cellStyle = theme.textTheme.labelLarge;
    final card = GlassPanel(
      radius: 10,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            // Auto-fit so the full date always shows, shrinking only on the
            // narrowest phones rather than clipping to "2026-07-…".
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_dateFormat.format(date), maxLines: 1, style: cellStyle),
                  Text(_timeFormat.format(date),
                      maxLines: 1,
                      style: cellStyle?.copyWith(color: p.textFaint)),
                ],
              ),
            ),
          ),
          if (_hasSplits) ...[
            _splitCell(theme, result.recognitionMs),
            _splitCell(theme, result.executionMs),
            const SizedBox(width: _splitGap),
          ],
          SizedBox(
            width: _timeColumnWidth,
            child: Text(timeToString(result.resultMs, fractionDigits: 2),
                maxLines: 1,
                style: cellStyle,
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );

    return Padding(
      key: ValueKey(result.id),
      padding: const EdgeInsets.only(bottom: 7),
      child: SwipeableRow(
        rowId: result.id,
        openRow: _openRow,
        enabled: true,
        peekHint: peekHint,
        deleteLabel: AppLocalizations.of(context)!.delete,
        radius: 10,
        onDelete: () => _deleteRow(result),
        child: card,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content;
    if (_loading) {
      content = Center(child: CircularProgressIndicator());
    } else if (_results.isEmpty) {
      content = Center(
        child: Text(AppLocalizations.of(context)!.noRecordedTimes,
            style: theme.textTheme.labelLarge),
      );
    } else {
      content = Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) =>
                  _buildRow(theme, _results[index], index == 0),
            ),
          ),
        ],
      );
    }

    return AppScaffold(
      title: widget.alg,
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15),
        child: content,
      ),
    );
  }
}
