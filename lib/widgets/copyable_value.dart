import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';
import '../theme/theme_scope.dart';

/// A `label: value` line with a button that copies the value — for values the
/// user has to retype somewhere else (the cube's MAC, the contact address).
class CopyableValue extends StatelessWidget {
  final String label;
  final String value;

  const CopyableValue({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    return Row(
      children: [
        Text('$label: ',
            style: TextStyle(fontSize: 13, color: p.textMuted)),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
                fontSize: 13, color: p.textPrimary, fontFamily: MONO_FONT),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 18),
          color: p.accent,
          tooltip: l10n.copy,
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(ClipboardData(text: value));
            messenger.showSnackBar(SnackBar(
              content: Text(l10n.copiedToClipboard),
              duration: const Duration(milliseconds: 1500),
            ));
          },
        ),
      ],
    );
  }
}
