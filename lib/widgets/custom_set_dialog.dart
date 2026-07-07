import 'package:flutter/material.dart';
import 'package:three_style_trainer/alg_structs.dart';

import '../l10n/app_localizations.dart';
import '../theme/theme_scope.dart';

class CustomSetDialog extends StatelessWidget {
  final bool Function(CustomSet) _onSaved;
  final _nameController = TextEditingController();
  final _algsController = TextEditingController();
  final bool _isEditing;

  CustomSetDialog.create(this._onSaved) : _isEditing = false;

  CustomSetDialog.edit(this._onSaved, CustomSet set) : _isEditing = true {
    _nameController.text = set.name;
    _algsController.text = set.algs.join('\n');
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
      title: Text(_isEditing ? l10n.editCustomSet : l10n.createCustomSet),
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
              controller: _nameController,
            ),
            const SizedBox(height: 16),
            TextField(
              style: textStyle,
              decoration: _inputDecoration(context, l10n.customSetAlgs,
                  helper: l10n.customSetAlgsHelper),
              keyboardType: TextInputType.multiline,
              minLines: 3,
              maxLines: 6,
              controller: _algsController,
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
            List<String> split = _algsController.text.split(RegExp(r'\n|,'));
            List<String> algs = [];
            for (String origAlg in split) {
              String alg = origAlg.trim();
              if (alg.isNotEmpty) {
                algs.add(alg);
              }
            }
            var customSet = CustomSet(_nameController.text, algs);
            if (_onSaved(customSet)) {
              Navigator.of(context).pop('save');
            }
          },
        ),
      ],
    );
  }
}
