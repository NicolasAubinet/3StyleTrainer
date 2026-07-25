import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../alg_structs.dart';
import '../database_manager.dart';
import '../export_data.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';
import '../theme/theme_scope.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/glass_panel.dart';
import '../widgets/swipeable_row.dart';

// Lists every recorded slip for one (algType, alg): what the cube read it as and
// the moves it saw turned. Each slip swipes to delete (like the times detail),
// with undo.
class AlgErrorDetailsScreen extends StatefulWidget {
  final AlgType algType;
  final String alg;
  final int? sinceMs;

  const AlgErrorDetailsScreen({
    super.key,
    required this.algType,
    required this.alg,
    this.sinceMs,
  });

  @override
  State<AlgErrorDetailsScreen> createState() => _AlgErrorDetailsScreenState();
}

class _AlgErrorDetailsScreenState extends State<AlgErrorDetailsScreen> {
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  final DateFormat _timeFormat = DateFormat('HH:mm:ss');

  List<AlgMistakeEntry> _entries = [];
  bool _loading = true;
  final ValueNotifier<Object?> _openRow = ValueNotifier<Object?>(null);

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
    final entries = await DatabaseManager()
        .getAlgMistakes(widget.algType, widget.alg, sinceMs: widget.sinceMs);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  String _kindLabel(AlgMistakeEntry e, AppLocalizations l10n) {
    switch (e.kind) {
      case AlgMistakeKind.wrongCase:
        return e.executed != null ? l10n.mistakeExecuted(e.executed!) : "–";
      case AlgMistakeKind.requeued:
        return l10n.mistakeRequeued;
      case AlgMistakeKind.skipped:
        return l10n.mistakeSkipped;
      case AlgMistakeKind.recovered:
        return l10n.mistakeRecovered;
      case null:
        return "–";
    }
  }

  // Delete by content (algType, alg, timestamp) so an undo re-insert round-trips
  // without a stale id — matches the times detail.
  void _deleteEntry(AlgMistakeEntry entry) {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _entries.remove(entry);
      _openRow.value = null;
    });
    DatabaseManager().deleteMistake(widget.algType, widget.alg, entry.timestamp);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text.rich(
            algTextSpan(l10n.deletedError(widget.alg), const TextStyle())),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () {
            DatabaseManager().importRecordedMistakes([
              RecordedMistake(
                widget.algType.name,
                widget.alg,
                entry.kind?.name ?? "",
                entry.timestamp,
                executed: entry.executed,
                moves: entry.moves,
              ),
            ]);
            setState(() => _load());
          },
        ),
      ));
  }

  Widget _row(ThemeData theme, AlgMistakeEntry e, AppLocalizations l10n,
      bool peekHint) {
    final p = context.palette;
    final date = DateTime.fromMillisecondsSinceEpoch(e.timestamp);
    final cellStyle = theme.textTheme.labelLarge;
    final card = GlassPanel(
      radius: 10,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_dateFormat.format(date),
                        maxLines: 1, style: cellStyle),
                    Text(_timeFormat.format(date),
                        maxLines: 1,
                        style: cellStyle?.copyWith(color: p.textFaint)),
                  ],
                ),
              ),
              Text.rich(algTextSpan(
                  _kindLabel(e, l10n),
                  cellStyle?.copyWith(
                          color: p.bad, fontWeight: FontWeight.w700) ??
                      const TextStyle())),
            ],
          ),
          if (e.moves != null) ...[
            const SizedBox(height: 6),
            Text(e.moves!,
                style: TextStyle(
                    fontFamily: MONO_FONT, fontSize: 13, color: p.textMuted)),
          ],
        ],
      ),
    );

    return Padding(
      key: ValueKey(e.timestamp),
      padding: const EdgeInsets.only(bottom: 7),
      child: SwipeableRow(
        rowId: e.timestamp,
        openRow: _openRow,
        enabled: true,
        peekHint: peekHint,
        deleteLabel: l10n.delete,
        radius: 10,
        onDelete: () => _deleteEntry(e),
        child: card,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_entries.isEmpty) {
      content = Center(
        child: Text(l10n.noRecordedErrors, style: theme.textTheme.labelLarge),
      );
    } else {
      content = ListView.builder(
        itemCount: _entries.length,
        itemBuilder: (context, i) => _row(theme, _entries[i], l10n, i == 0),
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
