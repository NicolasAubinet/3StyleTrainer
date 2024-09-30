import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:three_style_trainer/alg_structs.dart';

class CustomSetDialog extends StatelessWidget {
  final bool Function(CustomSet) _onSaved;
  final _nameController = TextEditingController();
  final _algsController = TextEditingController();

  CustomSetDialog(this._onSaved);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        AppLocalizations.of(context)!.newCustomSet,
      ),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.of(context)!.customSetName,
            textAlign: TextAlign.left,
          ),
          TextField(
            keyboardType: TextInputType.name,
            controller: _nameController,
          ),
          Text(
            AppLocalizations.of(context)!.customSetAlgs,
            textAlign: TextAlign.left,
          ),
          TextField(
            keyboardType: TextInputType.multiline,
            minLines: 1,
            maxLines: 6,
            controller: _algsController,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          style: TextButton.styleFrom(
            textStyle: Theme.of(context).textTheme.labelLarge,
          ),
          child: Text(AppLocalizations.of(context)!.close),
          onPressed: () async {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          style: TextButton.styleFrom(
            textStyle: Theme.of(context).textTheme.labelLarge,
          ),
          child: Text(AppLocalizations.of(context)!.save),
          onPressed: () {
            List<String> allAlgs = _algsController.text.split(RegExp(r'\n|,'));
            allAlgs.removeWhere((s) {
              return s.trim().isEmpty;
            });
            var customSet = CustomSet(_nameController.text, allAlgs);
            if (_onSaved(customSet)) {
              Navigator.of(context).pop('save');
            }
          },
        ),
      ],
    );
  }
}
