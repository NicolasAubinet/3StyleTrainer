import 'alg_structs.dart';

// A single recorded solve, as carried in an export file.
class RecordedTime {
  final String algType;
  final String alg;
  final int resultMs;
  final int timestamp;

  const RecordedTime(this.algType, this.alg, this.resultMs, this.timestamp);

  Map<String, Object?> toJson() => {
        'algType': algType,
        'alg': alg,
        'resultMs': resultMs,
        'timestamp': timestamp,
      };

  RecordedTime.fromJson(Map<String, Object?> json)
      : algType = json['algType'] as String,
        alg = json['alg'] as String,
        resultMs = (json['resultMs'] as num).toInt(),
        timestamp = (json['timestamp'] as num).toInt();
}

/// A portable, versioned snapshot of the user's data. Serializes to the
/// `three-style-trainer-export` JSON envelope. A section is `null` when it was
/// not included in the file (selective export in 1C); in a full export all
/// three are present.
class ExportData {
  static const String kFormat = "three-style-trainer-export";
  static const int kCurrentFormatVersion = 1;

  final int formatVersion;
  final int dbVersion;
  final int exportedAt;
  final List<RecordedTime>? recordedTimes;
  final List<CustomSet>? customSets;
  final Map<String, Object?>? settings;

  ExportData({
    this.formatVersion = kCurrentFormatVersion,
    required this.dbVersion,
    required this.exportedAt,
    this.recordedTimes,
    this.customSets,
    this.settings,
  });

  Map<String, Object?> toJson() {
    final sections = <String, Object?>{};
    if (recordedTimes != null) {
      sections['recordedTimes'] =
          recordedTimes!.map((e) => e.toJson()).toList();
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

  factory ExportData.fromJson(Map<String, Object?> json) {
    final sections = (json['sections'] as Map?)?.cast<String, Object?>() ?? {};

    final rawTimes = sections['recordedTimes'] as List?;
    final rawSets = sections['customSets'] as List?;
    final rawSettings = sections['settings'] as Map?;

    return ExportData(
      formatVersion: (json['formatVersion'] as num).toInt(),
      dbVersion: (json['dbVersion'] as num).toInt(),
      exportedAt: (json['exportedAt'] as num).toInt(),
      recordedTimes: rawTimes
          ?.map((e) => RecordedTime.fromJson((e as Map).cast<String, Object?>()))
          .toList(),
      customSets: rawSets
          ?.map((e) => CustomSet.fromMap((e as Map).cast<String, Object?>()))
          .toList(),
      settings: rawSettings?.cast<String, Object?>(),
    );
  }
}
