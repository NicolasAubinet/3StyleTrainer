import 'dart:convert';

import 'alg_structs.dart';

// Why an import couldn't proceed, surfaced to the user as a friendly message.
enum ImportErrorType {
  invalidFile, // not JSON, or structurally corrupt
  unknownFormat, // missing/unexpected "format" field
  unsupportedVersion, // formatVersion newer than this app understands
}

class ImportException implements Exception {
  final ImportErrorType type;
  ImportException(this.type);
}

// A single recorded solve, as carried in an export file. recognitionMs is the
// smart-cube recognition split (format v2+); null/absent for press-timed solves
// and v1 files.
class RecordedTime {
  final String algType;
  final String alg;
  final int resultMs;
  final int timestamp;
  final int? recognitionMs;

  const RecordedTime(this.algType, this.alg, this.resultMs, this.timestamp,
      {this.recognitionMs});

  Map<String, Object?> toJson() => {
        'algType': algType,
        'alg': alg,
        'resultMs': resultMs,
        if (recognitionMs != null) 'recognitionMs': recognitionMs,
        'timestamp': timestamp,
      };

  RecordedTime.fromJson(Map<String, Object?> json)
      : algType = json['algType'] as String,
        alg = json['alg'] as String,
        resultMs = (json['resultMs'] as num).toInt(),
        timestamp = (json['timestamp'] as num).toInt(),
        recognitionMs = (json['recognitionMs'] as num?)?.toInt();
}

// A single recorded mistake, as carried in an export file (format v3+). [kind]
// is an AlgMistakeKind name; [executed] is the pair the cube saw, absent for a
// requeue.
class RecordedMistake {
  final String algType;
  final String alg;
  final String kind;
  final int timestamp;
  final String? executed;

  const RecordedMistake(this.algType, this.alg, this.kind, this.timestamp,
      {this.executed});

  Map<String, Object?> toJson() => {
        'algType': algType,
        'alg': alg,
        'kind': kind,
        if (executed != null) 'executed': executed,
        'timestamp': timestamp,
      };

  RecordedMistake.fromJson(Map<String, Object?> json)
      : algType = json['algType'] as String,
        alg = json['alg'] as String,
        kind = json['kind'] as String,
        timestamp = (json['timestamp'] as num).toInt(),
        executed = json['executed'] as String?;
}

/// A portable, versioned snapshot of the user's data. Serializes to the
/// `three-style-trainer-export` JSON envelope. A section is `null` when it was
/// not included in the file (selective export in 1C); in a full export all
/// three are present.
class ExportData {
  static const String kFormat = "three-style-trainer-export";
  // v2 adds the optional recognitionMs split to recordedTimes; v3 adds the
  // mistakes section (both travel with the recorded-times category).
  static const int kCurrentFormatVersion = 3;

  final int formatVersion;
  final int dbVersion;
  final int exportedAt;
  final List<RecordedTime>? recordedTimes;
  final List<RecordedMistake>? mistakes;
  final List<CustomSet>? customSets;
  final Map<String, Object?>? settings;

  ExportData({
    this.formatVersion = kCurrentFormatVersion,
    required this.dbVersion,
    required this.exportedAt,
    this.recordedTimes,
    this.mistakes,
    this.customSets,
    this.settings,
  });

  Map<String, Object?> toJson() {
    final sections = <String, Object?>{};
    if (recordedTimes != null) {
      sections['recordedTimes'] =
          recordedTimes!.map((e) => e.toJson()).toList();
    }
    if (mistakes != null) {
      sections['mistakes'] = mistakes!.map((e) => e.toJson()).toList();
    }
    if (customSets != null) {
      sections['customSets'] =
          customSets!.map((e) => {'name': e.name, 'algs': e.algsToString()}).toList();
    }
    if (settings != null) {
      sections['settings'] = settings;
    }
    return {
      'format': kFormat,
      'formatVersion': formatVersion,
      'dbVersion': dbVersion,
      'exportedAt': exportedAt,
      'sections': sections,
    };
  }

  // Parse and validate a raw export file. Throws [ImportException] with a
  // categorized reason on anything we can't safely import.
  static ExportData parse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw ImportException(ImportErrorType.invalidFile);
    }
    if (decoded is! Map) {
      throw ImportException(ImportErrorType.invalidFile);
    }
    final json = decoded.cast<String, Object?>();

    if (json['format'] != kFormat) {
      throw ImportException(ImportErrorType.unknownFormat);
    }
    final formatVersion = json['formatVersion'];
    if (formatVersion is! num) {
      throw ImportException(ImportErrorType.invalidFile);
    }
    if (formatVersion > kCurrentFormatVersion) {
      throw ImportException(ImportErrorType.unsupportedVersion);
    }

    try {
      return ExportData.fromJson(json);
    } catch (_) {
      throw ImportException(ImportErrorType.invalidFile);
    }
  }

  factory ExportData.fromJson(Map<String, Object?> json) {
    final sections = (json['sections'] as Map?)?.cast<String, Object?>() ?? {};

    final rawTimes = sections['recordedTimes'] as List?;
    final rawMistakes = sections['mistakes'] as List?;
    final rawSets = sections['customSets'] as List?;
    final rawSettings = sections['settings'] as Map?;

    return ExportData(
      formatVersion: (json['formatVersion'] as num).toInt(),
      dbVersion: (json['dbVersion'] as num).toInt(),
      exportedAt: (json['exportedAt'] as num).toInt(),
      recordedTimes: rawTimes
          ?.map((e) => RecordedTime.fromJson((e as Map).cast<String, Object?>()))
          .toList(),
      mistakes: rawMistakes
          ?.map((e) =>
              RecordedMistake.fromJson((e as Map).cast<String, Object?>()))
          .toList(),
      customSets: rawSets
          ?.map((e) => CustomSet.fromMap((e as Map).cast<String, Object?>()))
          .toList(),
      settings: rawSettings?.cast<String, Object?>(),
    );
  }
}
