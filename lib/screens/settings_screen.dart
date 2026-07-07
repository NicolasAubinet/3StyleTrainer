import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:three_style_trainer/export_data.dart';
import 'package:three_style_trainer/settings.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';
import '../theme/theme_controller.dart';
import '../theme/theme_scope.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_segmented_control.dart';
import '../widgets/glass_panel.dart';

class SettingsScreen extends StatefulWidget {
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _cornersSchemeTextController = TextEditingController();
  final _edgesSchemeTextController = TextEditingController();
  final _cornersFormKey = GlobalKey<FormState>();
  final _edgesFormKey = GlobalKey<FormState>();

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

  Widget _sectionLabel(String text) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              color: p.accent)),
    );
  }

  Widget _schemeCard({
    required String title,
    required TextEditingController controller,
    required GlobalKey<FormState> formKey,
    required void Function(PointerDownEvent) onTapOutside,
    String? hint,
  }) {
    final p = context.palette;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.textMuted)),
          const SizedBox(height: 8),
          Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              cursorColor: p.accent,
              onTapOutside: onTapOutside,
              onChanged: (_) => formKey.currentState!.validate(),
              validator: (value) => _validateScheme(context, value),
              style: TextStyle(
                  fontFamily: MONO_FONT,
                  fontSize: 15,
                  letterSpacing: 1.5,
                  color: p.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: p.inputFill,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: p.panelBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: p.panelBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: p.accent),
                ),
              ),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint, style: TextStyle(fontSize: 10, color: p.textFaint)),
          ],
        ],
      ),
    );
  }

  Widget _bufferDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final p = context.palette;
    return Expanded(
      child: GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.textMuted)),
            const SizedBox(height: 6),
            SizedBox(
              height: 28,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: p.surfaceOpaque,
                  iconEnabledColor: p.textMuted,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary),
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _exportData(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final export = ExportData(
        dbVersion: DB_VERSION,
        exportedAt: DateTime.now().millisecondsSinceEpoch,
        recordedTimes: await DatabaseManager().getAllRecordedTimes(),
        customSets: await DatabaseManager().getCustomSets(),
        settings: await Settings().exportSettings(),
      );
      final bytes =
          Uint8List.fromList(utf8.encode(jsonEncode(export.toJson())));
      const fileName = 'three-style-trainer-export.json';
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(bytes, mimeType: 'application/json', name: fileName)
        ],
        fileNameOverrides: [fileName],
        subject: fileName,
      ));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.exportFailed(e.toString())),
        ));
      }
    }
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
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;

    return PopScope(
      onPopInvokedWithResult: _onWillPop,
      child: AppScaffold(
        title: l10n.settings,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(15, 6, 15, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel(l10n.appearance),
              GlassPanel(
                padding: const EdgeInsets.all(10),
                child: AppSegmentedControl<AppThemeId>(
                  selected: ThemeController().current,
                  options: AppThemeId.values
                      .map((id) =>
                          SegmentOption(id, id.getLocalizedName(context)))
                      .toList(),
                  onChanged: (id) {
                    ThemeController().set(id);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 18),
              _sectionLabel(l10n.schemesSection),
              _schemeCard(
                title: l10n.cornersScheme,
                controller: _cornersSchemeTextController,
                formKey: _cornersFormKey,
                onTapOutside: _onTapOutsideCornerScheme,
                hint: l10n.cornersPiecesOrder,
              ),
              const SizedBox(height: 12),
              _schemeCard(
                title: l10n.edgesScheme,
                controller: _edgesSchemeTextController,
                formKey: _edgesFormKey,
                onTapOutside: _onTapOutsideEdgesScheme,
              ),
              const SizedBox(height: 18),
              _sectionLabel(l10n.buffersSection),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bufferDropdown<CornerBuffer>(
                    label: l10n.cornerBuffer,
                    value: Settings().getCornerBuffer(),
                    items: CornerBuffer.values
                        .map((b) =>
                            DropdownMenuItem(value: b, child: Text(b.name)))
                        .toList(),
                    onChanged: (b) {
                      if (b != null) {
                        Settings().setCornerBuffer(b);
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  _bufferDropdown<EdgeBuffer>(
                    label: l10n.edgeBuffer,
                    value: Settings().getEdgeBuffer(),
                    items: EdgeBuffer.values
                        .map((b) =>
                            DropdownMenuItem(value: b, child: Text(b.name)))
                        .toList(),
                    onChanged: (b) {
                      if (b != null) {
                        Settings().setEdgeBuffer(b);
                        setState(() {});
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 28),
              GlassPanel(
                onTap: () => _exportData(context),
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.ios_share_rounded, color: p.accent, size: 20),
                    const SizedBox(width: 8),
                    Text(l10n.exportData,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.accent)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassPanel(
                onTap: () => _confirmClearAllTimes(context),
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_forever_rounded, color: p.bad, size: 20),
                    const SizedBox(width: 8),
                    Text(l10n.clearAllTimes,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.bad)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
