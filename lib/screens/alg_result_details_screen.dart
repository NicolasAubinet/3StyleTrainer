import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../alg_structs.dart';
import '../database_manager.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_scope.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/sort_header.dart';

enum _SortColumn { dateTime, result }

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
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd - HH:mm:ss');

  List<AlgResult> _results = [];
  bool _loading = true;
  // Sort: by solve time or by date/time (default). Not persisted.
  final SortState<_SortColumn> _sort = SortState(
      column: _SortColumn.dateTime, direction: SortDirection.descending);

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
    results.sort((a, b) {
      final cmp = _sort.column == _SortColumn.result
          ? a.resultMs.compareTo(b.resultMs)
          : a.timestamp.compareTo(b.timestamp);
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
  static const double _timeColumnWidth = 90;
  static const double _deleteColumnWidth = 48;

  // Uses the shared [SortState] but keeps its own header layout (fixed-width,
  // right-aligned time column) rather than the list-style [SortHeader] widget.
  Widget _sortHeader(ThemeData theme, String label, _SortColumn column,
      {double? width, TextAlign align = TextAlign.left}) {
    final active = _sort.isActive(column);
    final arrow = active ? _sort.direction.arrow : "";
    final text = Text(
      "$label$arrow",
      textAlign: align,
      style: theme.textTheme.titleSmall
          ?.copyWith(color: active ? context.palette.accent : null),
    );
    return InkWell(
      onTap: () => _onSort(column),
      child: width == null ? text : SizedBox(width: width, child: text),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
              child: _sortHeader(
                  theme, l10n.columnDateTime, _SortColumn.dateTime)),
          _sortHeader(theme, l10n.columnResult, _SortColumn.result,
              width: _timeColumnWidth, align: TextAlign.right),
          SizedBox(width: _deleteColumnWidth),
        ],
      ),
    );
  }

  Widget _buildRow(ThemeData theme, AlgResult result) {
    final date = DateTime.fromMillisecondsSinceEpoch(result.timestamp);
    final cellStyle = theme.textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        children: [
          Expanded(child: Text(_dateFormat.format(date), style: cellStyle)),
          SizedBox(
            width: _timeColumnWidth,
            child: Text(timeToString(result.resultMs, fractionDigits: 2),
                style: cellStyle, textAlign: TextAlign.right),
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
          _buildHeader(theme),
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
