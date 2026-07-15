import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../alg_structs.dart';
import '../database_manager.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_scope.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/sort_header.dart';

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

  void _confirmDelete(AlgResult result) async {
    bool confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteTimeConfirmTitle),
        content: Text(AppLocalizations.of(context)!.deleteTimeConfirmMessage),
        actions: [
          TextButton(
            child: Text(AppLocalizations.of(context)!.cancel),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: Text(AppLocalizations.of(context)!.delete),
            onPressed: () {
              confirmed = true;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );

    if (confirmed) {
      DatabaseManager().deleteResult(result.id);
      setState(() {
        _results.removeWhere((r) => r.id == result.id);
      });
    }
  }

  // Keep these widths in sync between the header and the rows so columns align.
  // Kept tight so the date column has room to show the full date on its line.
  static const double _timeColumnWidth = 58;
  static const double _deleteColumnWidth = 34;
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
      // Card margin (4) + row padding (16), so headers sit over their values.
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
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
          SizedBox(width: _deleteColumnWidth),
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

  Widget _buildRow(ThemeData theme, AlgResult result) {
    final date = DateTime.fromMillisecondsSinceEpoch(result.timestamp);
    final p = context.palette;
    final cellStyle = theme.textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
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
          SizedBox(
            width: _deleteColumnWidth,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.delete),
              color: context.palette.textMuted,
              onPressed: () => _confirmDelete(result),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;

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
          Expanded(
            child: Card(
              color: p.panel,
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) =>
                    _buildRow(theme, _results[index]),
              ),
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
