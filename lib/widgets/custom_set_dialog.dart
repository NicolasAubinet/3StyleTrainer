import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:three_style_trainer/alg_structs.dart';

class CustomSetDialog extends StatelessWidget {
  final bool Function(CustomSet) _onSaved;
  final _nameController = TextEditingController();
  final _algsController = TextEditingController();
  bool _isEditing;

  CustomSetDialog.create(this._onSaved) : _isEditing = false;

  CustomSetDialog.edit(this._onSaved, CustomSet set) : _isEditing = true {
    _nameController.text = set.name;
    _algsController.text = set.algs.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEditing
            ? AppLocalizations.of(context)!.editCustomSet
            : AppLocalizations.of(context)!.createCustomSet,
      ),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: InputDecoration(
              border: UnderlineInputBorder(),
              labelText: AppLocalizations.of(context)!.customSetName,
              labelStyle: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(color: Colors.black),
            ),
            keyboardType: TextInputType.name,
            controller: _nameController,
          ),
          SizedBox(height: 5),
          TextField(
            decoration: InputDecoration(
              border: UnderlineInputBorder(),
              labelText: AppLocalizations.of(context)!.customSetAlgs,
              labelStyle: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(color: Colors.black),
            ),
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
