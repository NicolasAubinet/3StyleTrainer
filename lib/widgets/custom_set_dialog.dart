import 'package:flutter/material.dart';
import 'package:three_style_trainer/alg_structs.dart';

import '../l10n/app_localizations.dart';
import '../theme/theme_scope.dart';
import 'tap_select_all.dart';

class CustomSetDialog extends StatefulWidget {
  final bool Function(CustomSet) onSaved;
  final bool isEditing;
  final CustomSet? initialSet;

  const CustomSetDialog.create(this.onSaved)
      : isEditing = false,
        initialSet = null;

  const CustomSetDialog.edit(this.onSaved, CustomSet set)
      : isEditing = true,
        initialSet = set;

  @override
  State<CustomSetDialog> createState() => _CustomSetDialogState();
}

class _CustomSetDialogState extends State<CustomSetDialog> {
  late final TapSelectAll _name = TapSelectAll(
      TextEditingController(text: widget.initialSet?.name ?? ''));
  late final TapSelectAll _algs = TapSelectAll(TextEditingController(
      text: widget.initialSet == null
          ? ''
          : widget.initialSet!.algs.join('\n')));

  @override
  void dispose() {
    _name.controller.dispose();
    _algs.controller.dispose();
    _name.dispose();
    _algs.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(BuildContext context, String label,
      {String? helper}) {
    final p = context.palette;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperStyle: TextStyle(color: p.textFaint),
      labelStyle: TextStyle(color: p.textMuted),
      floatingLabelStyle: TextStyle(color: p.accent),
      filled: true,
      fillColor: p.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: border(p.panelBorder, 1),
      focusedBorder: border(p.accent, 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final textStyle = TextStyle(color: p.textPrimary);

    return AlertDialog(
      title: Text(widget.isEditing ? l10n.editCustomSet : l10n.createCustomSet),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              style: textStyle,
              decoration: _inputDecoration(context, l10n.customSetName),
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              controller: _name.controller,
              focusNode: _name.focusNode,
              onTap: _name.onTap,
            ),
            const SizedBox(height: 16),
            TextField(
              style: textStyle,
              decoration: _inputDecoration(context, l10n.customSetAlgs,
                  helper: l10n.customSetAlgsHelper),
              keyboardType: TextInputType.multiline,
              minLines: 3,
              maxLines: 6,
              controller: _algs.controller,
              focusNode: _algs.focusNode,
              onTap: _algs.onTap,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(l10n.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        FilledButton(
          child: Text(l10n.save),
          onPressed: () {
            List<String> split = _algs.controller.text.split(RegExp(r'\n|,'));
            List<String> algs = [];
            for (String origAlg in split) {
              String alg = origAlg.trim();
              if (alg.isNotEmpty) {
                algs.add(alg);
              }
            }
            var customSet = CustomSet(_name.controller.text, algs);
            if (widget.onSaved(customSet)) {
              Navigator.of(context).pop('save');
            }
          },
        ),
      ],
    );
  }
}
