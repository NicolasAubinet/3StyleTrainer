import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';
import '../theme/theme_scope.dart';

// The three data categories that export/import can carry, in display order.
enum DataCategory { recordedTimes, customSets, settings }

const Set<DataCategory> allDataCategories = {
  DataCategory.recordedTimes,
  DataCategory.customSets,
  DataCategory.settings,
};

// Shared category picker for both export and import. [available] is the set of
// categories the user may toggle (for import: only the sections present in the
// file); the rest are shown greyed and unchecked. Returns the chosen categories,
// or null if cancelled. Never returns an empty set (confirm is disabled then).
Future<Set<DataCategory>?> showDataCategoryDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  Set<DataCategory> available = allDataCategories,
}) {
  return showDialog<Set<DataCategory>>(
    context: context,
    builder: (_) => _DataCategoryDialog(
      title: title,
      confirmLabel: confirmLabel,
      available: available,
    ),
  );
}

class _DataCategoryDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final Set<DataCategory> available;

  const _DataCategoryDialog({
    required this.title,
    required this.confirmLabel,
    required this.available,
  });

  @override
  State<_DataCategoryDialog> createState() => _DataCategoryDialogState();
}

class _DataCategoryDialogState extends State<_DataCategoryDialog> {
  late final Set<DataCategory> _selected = {...widget.available};

  String _label(AppLocalizations l10n, DataCategory c) {
    switch (c) {
      case DataCategory.recordedTimes:
        return l10n.categoryRecordedTimes;
      case DataCategory.customSets:
        return l10n.categoryCustomSets;
      case DataCategory.settings:
        return l10n.settings;
    }
  }

  Widget _row(AppLocalizations l10n, AppPalette p, DataCategory c) {
    final enabled = widget.available.contains(c);
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      activeColor: p.accent,
      title: Text(_label(l10n, c),
          style: TextStyle(color: enabled ? p.textPrimary : p.textFaint)),
      value: _selected.contains(c),
      onChanged: enabled
          ? (v) => setState(() {
                if (v == true) {
                  _selected.add(c);
                } else {
                  _selected.remove(c);
                }
              })
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final allOn = _selected.length == widget.available.length;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _selected
                  ..clear()
                  ..addAll(allOn ? const <DataCategory>{} : widget.available);
              }),
              child: Text(allOn ? l10n.deselectAll : l10n.selectAll),
            ),
          ),
          for (final c in allDataCategories) _row(l10n, p, c),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop({..._selected}),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
