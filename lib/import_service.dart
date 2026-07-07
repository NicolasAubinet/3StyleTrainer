import 'database_manager.dart';
import 'export_data.dart';
import 'settings.dart';
import 'theme/theme_controller.dart';

// Outcome of a successful import, for the result view.
class ImportResult {
  final int recordedTimesImported;
  final int customSetsImported;
  final List<String> skippedCustomSets;
  final bool settingsApplied;

  const ImportResult({
    required this.recordedTimesImported,
    required this.customSetsImported,
    required this.skippedCustomSets,
    required this.settingsApplied,
  });
}

// Applies a parsed [ExportData] to local storage using the merge/conflict rules,
// then refreshes the affected in-memory state.
Future<ImportResult> applyImport(ExportData data) async {
  int recordedTimesImported = 0;
  if (data.recordedTimes != null) {
    recordedTimesImported =
        await DatabaseManager().importRecordedTimes(data.recordedTimes!);
  }

  int customSetsImported = 0;
  List<String> skippedCustomSets = const [];
  if (data.customSets != null) {
    skippedCustomSets =
        await DatabaseManager().importCustomSets(data.customSets!);
    customSetsImported = data.customSets!.length - skippedCustomSets.length;
  }

  final bool settingsApplied = data.settings != null;
  if (settingsApplied) {
    await Settings().importSettings(data.settings!);
    await ThemeController().load();
  }

  return ImportResult(
    recordedTimesImported: recordedTimesImported,
    customSetsImported: customSetsImported,
    skippedCustomSets: skippedCustomSets,
    settingsApplied: settingsApplied,
  );
}
