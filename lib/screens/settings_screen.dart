import 'package:flutter/material.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:three_style_trainer/settings.dart';

import '../l10n/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _cornersSchemeTextController = TextEditingController();
  final _edgesSchemeTextController = TextEditingController();
  final _cornersFormKey = GlobalKey<FormState>();
  final _edgesFormKey = GlobalKey<FormState>();
  final _cardColor = Color(0x44000000);

  @override
  void initState() {
    super.initState();
    _cornersSchemeTextController.text = Settings().getCornersScheme().join();
    _edgesSchemeTextController.text = Settings().getEdgesScheme().join();
  }

  void _onTapOutsideCornerScheme(PointerDownEvent event) async {
    if (_cornersFormKey.currentState!.validate()) {
      Settings().setCornersScheme(_cornersSchemeTextController.text);
    }
  }

  void _onTapOutsideEdgesScheme(PointerDownEvent event) async {
    if (_edgesFormKey.currentState!.validate()) {
      Settings().setEdgesScheme(_edgesSchemeTextController.text);
    }
  }

  Future<bool> _onWillPop(bool didPop, Object? result) async {
    if (_cornersFormKey.currentState!.validate()) {
      Settings().setCornersScheme(_cornersSchemeTextController.text);
    }
    if (_edgesFormKey.currentState!.validate()) {
      Settings().setEdgesScheme(_edgesSchemeTextController.text);
    }
    return true;
  }

  void _onChangedCornersScheme(String scheme) {
    _cornersFormKey.currentState!.validate();
  }

  void _onChangedEdgesScheme(String scheme) {
    _edgesFormKey.currentState!.validate();
  }

  String? _validateScheme(BuildContext context, String? scheme) {
    var localizations = AppLocalizations.of(context)!;
    if (scheme == null || scheme.isEmpty) {
      return localizations.enterScheme;
    }

    const int expectedSize = SPEFFZ.length;
    if (scheme.length != expectedSize) {
      return localizations.invalidSchemeSize(expectedSize);
    }

    List<String> previousChars = [];
    for (var char in scheme.toLowerCase().split('')) {
      if (previousChars.contains(char)) {
        return localizations.schemeCannotHaveDuplicates;
      }
      previousChars.add(char);
    }

    return null;
  }

  Widget getCornersSchemeWidget(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: _cardColor,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppLocalizations.of(context)!.cornersScheme,
                style: theme.textTheme.displaySmall!.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.normal),
              ),
            ),
            Form(
              key: _cornersFormKey,
              child: TextFormField(
                style: theme.textTheme.labelLarge,
                cursorColor: theme.colorScheme.onPrimary,
                keyboardType: TextInputType.text,
                controller: _cornersSchemeTextController,
                onTapOutside: _onTapOutsideCornerScheme,
                onChanged: _onChangedCornersScheme,
                validator: (value) {
                  return _validateScheme(context, value);
                },
              ),
            ),
            Text(
              AppLocalizations.of(context)!.cornersPiecesOrder,
              style: theme.textTheme.labelSmall!.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget getEdgesSchemeWidget(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: _cardColor,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppLocalizations.of(context)!.edgesScheme,
                style: theme.textTheme.displaySmall!.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.normal),
              ),
            ),
            Form(
              key: _edgesFormKey,
              child: TextFormField(
                style: theme.textTheme.labelLarge,
                cursorColor: theme.colorScheme.onPrimary,
                keyboardType: TextInputType.text,
                controller: _edgesSchemeTextController,
                onTapOutside: _onTapOutsideEdgesScheme,
                onChanged: _onChangedEdgesScheme,
                validator: (value) {
                  return _validateScheme(context, value);
                },
              ),
            ),
            Text(
              AppLocalizations.of(context)!.edgesPiecesOrder,
              style: theme.textTheme.labelSmall!.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget getCornerBufferWidget(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: _cardColor,
      child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: DropdownMenu<CornerBuffer>(
            initialSelection: Settings().getCornerBuffer(),
            textStyle: theme.textTheme.labelSmall,
            label: Text(
              AppLocalizations.of(context)!.cornerBuffer,
              style: theme.textTheme.labelSmall,
            ),
            onSelected: (CornerBuffer? buffer) {
              if (buffer != null) {
                Settings().setCornerBuffer(buffer);
              }
            },
            dropdownMenuEntries: CornerBuffer.values
                .map<DropdownMenuEntry<CornerBuffer>>((CornerBuffer type) {
              return DropdownMenuEntry<CornerBuffer>(
                value: type,
                label: type.name,
                style: MenuItemButton.styleFrom(
                  textStyle: theme.textTheme.labelSmall,
                ),
              );
            }).toList(),
          )),
    );
  }

  Widget getEdgeBufferWidget(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: _cardColor,
      child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: DropdownMenu<EdgeBuffer>(
            initialSelection: Settings().getEdgeBuffer(),
            textStyle: theme.textTheme.labelSmall,
            label: Text(
              AppLocalizations.of(context)!.edgeBuffer,
              style: theme.textTheme.labelSmall,
            ),
            onSelected: (EdgeBuffer? buffer) {
              if (buffer != null) {
                Settings().setEdgeBuffer(buffer);
              }
            },
            dropdownMenuEntries: EdgeBuffer.values
                .map<DropdownMenuEntry<EdgeBuffer>>((EdgeBuffer type) {
              return DropdownMenuEntry<EdgeBuffer>(
                value: type,
                label: type.name,
                style: MenuItemButton.styleFrom(
                  textStyle: theme.textTheme.labelSmall,
                ),
              );
            }).toList(),
          )),
    );
  }

  Widget getClearTimesWidget(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
        icon: Icon(Icons.delete_forever, color: Colors.white),
        label: Text(
          AppLocalizations.of(context)!.clearAllTimes,
          style: const TextStyle(color: Colors.white),
        ),
        onPressed: () => _confirmClearAllTimes(context),
      ),
    );
  }

  void _confirmClearAllTimes(BuildContext context) async {
    bool confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.clearAllTimes),
        content: Text(AppLocalizations.of(context)!.clearAllTimesConfirmMessage),
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
      DatabaseManager().clearAllResults();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.allTimesCleared),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      onPopInvokedWithResult: _onWillPop,
      child: Scaffold(
        backgroundColor: theme.colorScheme.primary,
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.settings),
        ),
        body: Padding(
          padding: const EdgeInsets.all(5.0),
          child: Column(
            children: [
              getCornersSchemeWidget(context),
              getEdgesSchemeWidget(context),
              Row(
                children: [
                  getCornerBufferWidget(context),
                  getEdgeBufferWidget(context),
                ],
              ),
              getClearTimesWidget(context),
            ],
          ),
        ),
      ),
    );
  }
}
