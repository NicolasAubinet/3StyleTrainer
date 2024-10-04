import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/settings.dart';

class SettingsScreen extends StatelessWidget {
  final _cornersSchemeTextController = TextEditingController();
  final _edgesSchemeTextController = TextEditingController();
  final _cornersFormKey = GlobalKey<FormState>();
  final _edgesFormKey = GlobalKey<FormState>();
  final _cardColor = Color(0x44000000);

  SettingsScreen() {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
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
            )
          ],
        ),
      ),
    );
  }
}
