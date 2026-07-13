import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:three_style_trainer/export_data.dart';
import 'package:three_style_trainer/import_service.dart';
import 'package:three_style_trainer/settings.dart';
import 'package:three_style_trainer/smart_cube/cube_orientation.dart';
import 'package:three_style_trainer/utils.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';
import '../theme/theme_controller.dart';
import '../theme/theme_scope.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_segmented_control.dart';
import '../widgets/data_category_dialog.dart';
import '../widgets/glass_panel.dart';
import '../widgets/tap_select_all.dart';

class SettingsScreen extends StatefulWidget {
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _cornersSchemeTextController = TextEditingController();
  final _edgesSchemeTextController = TextEditingController();
  final _cornersFormKey = GlobalKey<FormState>();
  final _edgesFormKey = GlobalKey<FormState>();
  late final _cornersSchemeTap = TapSelectAll(_cornersSchemeTextController);
  late final _edgesSchemeTap = TapSelectAll(_edgesSchemeTextController);

  @override
  void initState() {
    super.initState();
    _cornersSchemeTextController.text = Settings().getCornersScheme().join();
    _edgesSchemeTextController.text = Settings().getEdgesScheme().join();
  }

  @override
  void dispose() {
    _cornersSchemeTap.dispose();
    _edgesSchemeTap.dispose();
    _cornersSchemeTextController.dispose();
    _edgesSchemeTextController.dispose();
    super.dispose();
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
    required FocusNode focusNode,
    required VoidCallback onTap,
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
              focusNode: focusNode,
              onTap: onTap,
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
    final chosen = await showDataCategoryDialog(context,
        title: l10n.exportData, confirmLabel: l10n.export);
    if (chosen == null || !context.mounted) {
      return; // cancelled
    }
    try {
      final export = ExportData(
        dbVersion: DB_VERSION,
        exportedAt: DateTime.now().millisecondsSinceEpoch,
        recordedTimes: chosen.contains(DataCategory.recordedTimes)
            ? await DatabaseManager().getAllRecordedTimes()
            : null,
        // Errors are part of the practice history, so they follow the times.
        mistakes: chosen.contains(DataCategory.recordedTimes)
            ? await DatabaseManager().getAllRecordedMistakes()
            : null,
        customSets: chosen.contains(DataCategory.customSets)
            ? await DatabaseManager().getCustomSets()
            : null,
        settings: chosen.contains(DataCategory.settings)
            ? await Settings().exportSettings()
            : null,
      );
      final bytes =
          Uint8List.fromList(utf8.encode(jsonEncode(export.toJson())));
      const fileName = 'three-style-trainer-export.json';

      // The OS share sheet is unreliable on desktop, so save to a file there
      // (and on web, which downloads the file). Mobile keeps the share sheet.
      final isDesktop = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.macOS);
      if (kIsWeb || isDesktop) {
        final path = await FilePicker.saveFile(
          dialogTitle: l10n.exportData,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: bytes,
        );
        if (!kIsWeb && path == null) {
          return; // user cancelled the save dialog
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.exportSucceeded),
          ));
        }
      } else {
        await SharePlus.instance.share(ShareParams(
          files: [
            XFile.fromData(bytes, mimeType: 'application/json', name: fileName)
          ],
          fileNameOverrides: [fileName],
          subject: fileName,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.exportFailed(e.toString())),
        ));
      }
    }
  }

  void _importData(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      final bytes = picked?.files.singleOrNull?.bytes;
      if (bytes == null) {
        return; // user cancelled
      }

      final data = ExportData.parse(utf8.decode(bytes));

      final present = <DataCategory>{
        if (data.recordedTimes != null || data.mistakes != null)
          DataCategory.recordedTimes,
        if (data.customSets != null) DataCategory.customSets,
        if (data.settings != null) DataCategory.settings,
      };
      if (!context.mounted) return;

      ImportResult result;
      if (present.isEmpty) {
        result = await applyImport(data); // nothing to import
      } else {
        final chosen = await showDataCategoryDialog(context,
            title: l10n.importData,
            confirmLabel: l10n.import,
            available: present);
        if (chosen == null) return; // cancelled
        result = await applyImport(ExportData(
          formatVersion: data.formatVersion,
          dbVersion: data.dbVersion,
          exportedAt: data.exportedAt,
          recordedTimes: chosen.contains(DataCategory.recordedTimes)
              ? data.recordedTimes
              : null,
          mistakes:
              chosen.contains(DataCategory.recordedTimes) ? data.mistakes : null,
          customSets:
              chosen.contains(DataCategory.customSets) ? data.customSets : null,
          settings:
              chosen.contains(DataCategory.settings) ? data.settings : null,
        ));
      }

      if (!context.mounted) return;
      // Reflect any imported schemes/buffers in this screen.
      setState(() {
        _cornersSchemeTextController.text = Settings().getCornersScheme().join();
        _edgesSchemeTextController.text = Settings().getEdgesScheme().join();
      });
      _showImportResult(context, result);
    } on ImportException catch (e) {
      if (context.mounted) {
        _showImportError(context, _importErrorMessage(l10n, e.type));
      }
    } catch (e) {
      if (context.mounted) {
        _showImportError(context, l10n.importErrorInvalidFile);
      }
    }
  }

  String _importErrorMessage(AppLocalizations l10n, ImportErrorType type) {
    switch (type) {
      case ImportErrorType.invalidFile:
        return l10n.importErrorInvalidFile;
      case ImportErrorType.unknownFormat:
        return l10n.importErrorUnknownFormat;
      case ImportErrorType.unsupportedVersion:
        return l10n.importErrorUnsupportedVersion;
    }
  }

  void _showImportError(BuildContext context, String message) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.importData),
        content: Text(message),
        actions: [
          TextButton(
            child: Text(l10n.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _showImportResult(BuildContext context, ImportResult result) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.importSucceeded),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.importRecordedTimesCount(result.recordedTimesImported)),
              const SizedBox(height: 6),
              Text(l10n.importCustomSetsCount(result.customSetsImported)),
              if (result.settingsApplied) ...[
                const SizedBox(height: 6),
                Text(l10n.importSettingsApplied),
              ],
              if (result.skippedCustomSets.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.importSkippedCustomSets(result.skippedCustomSets.length),
                  style: TextStyle(color: p.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  result.skippedCustomSets.join(', '),
                  style: TextStyle(color: p.textFaint, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            child: Text(l10n.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
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
                focusNode: _cornersSchemeTap.focusNode,
                onTap: _cornersSchemeTap.onTap,
                hint: l10n.cornersPiecesOrder,
              ),
              const SizedBox(height: 12),
              _schemeCard(
                title: l10n.edgesScheme,
                controller: _edgesSchemeTextController,
                formKey: _edgesFormKey,
                onTapOutside: _onTapOutsideEdgesScheme,
                focusNode: _edgesSchemeTap.focusNode,
                onTap: _edgesSchemeTap.onTap,
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
              const SizedBox(height: 18),
              _sectionLabel(l10n.cubeOrientationSection),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bufferDropdown<CubeColour>(
                    label: l10n.cubeTopColour,
                    value: Settings().getCubeTopColour(),
                    items: CubeColour.values
                        .map((c) => DropdownMenuItem(
                            value: c, child: Text(cubeColourName(l10n, c))))
                        .toList(),
                    onChanged: (c) {
                      if (c != null) {
                        Settings().setCubeOrientation(
                            c, Settings().getCubeFrontColour());
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  _bufferDropdown<CubeColour>(
                    label: l10n.cubeFrontColour,
                    value: Settings().getCubeFrontColour(),
                    items: CubeOrientation.frontsFor(Settings().getCubeTopColour())
                        .map((c) => DropdownMenuItem(
                            value: c, child: Text(cubeColourName(l10n, c))))
                        .toList(),
                    onChanged: (c) {
                      if (c != null) {
                        Settings().setCubeOrientation(
                            Settings().getCubeTopColour(), c);
                        setState(() {});
                      }
                    },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(l10n.cubeOrientationHint,
                    style: TextStyle(fontSize: 10, color: p.textFaint)),
              ),
              const SizedBox(height: 18),
              _sectionLabel(l10n.optionsSection),
              GlassField(
                label: l10n.showRecordingDot,
                trailing: Switch(
                  value: Settings().getShowRecordingDot(),
                  onChanged: (v) {
                    Settings().setShowRecordingDot(v);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: GlassPanel(
                      onTap: () => _exportData(context),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.ios_share_rounded,
                              color: p.accent, size: 20),
                          const SizedBox(width: 8),
                          Text(l10n.exportData,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: p.accent)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassPanel(
                      onTap: () => _importData(context),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.file_download_rounded,
                              color: p.accent, size: 20),
                          const SizedBox(width: 8),
                          Text(l10n.importData,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: p.accent)),
                        ],
                      ),
                    ),
                  ),
                ],
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
