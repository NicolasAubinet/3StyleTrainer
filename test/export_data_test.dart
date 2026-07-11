import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/export_data.dart';

void main() {
  ExportData sample() => ExportData(
        dbVersion: 5,
        exportedAt: 1730000000000,
        recordedTimes: [
          RecordedTime('Corner', 'AB', 1234, 1730000000001,
              recognitionMs: 500),
          RecordedTime('Edge', 'CD', 5678, 1730000000002),
        ],
        customSets: [
          CustomSet('My set', ['AB', 'CD', 'EF']),
        ],
        settings: {
          'corners_scheme': 'ABCDEFGHIJKLMNOPQRSTUVWX',
          'show_next_alg': true,
          'target_time': 2.5,
        },
      );

  test('serialize -> parse round-trips all sections', () {
    final raw = jsonEncode(sample().toJson());
    final parsed = ExportData.parse(raw);

    expect(parsed.formatVersion, ExportData.kCurrentFormatVersion);
    expect(parsed.dbVersion, 5);
    expect(parsed.exportedAt, 1730000000000);

    expect(parsed.recordedTimes, hasLength(2));
    expect(parsed.recordedTimes![0].algType, 'Corner');
    expect(parsed.recordedTimes![0].alg, 'AB');
    expect(parsed.recordedTimes![0].resultMs, 1234);
    expect(parsed.recordedTimes![0].timestamp, 1730000000001);
    expect(parsed.recordedTimes![0].recognitionMs, 500);
    // The unsplit press-timed row carries no recognition.
    expect(parsed.recordedTimes![1].recognitionMs, isNull);

    expect(parsed.customSets, hasLength(1));
    expect(parsed.customSets![0].name, 'My set');
    expect(parsed.customSets![0].algs, ['AB', 'CD', 'EF']);

    expect(parsed.settings!['corners_scheme'], 'ABCDEFGHIJKLMNOPQRSTUVWX');
    expect(parsed.settings!['show_next_alg'], true);
    expect(parsed.settings!['target_time'], 2.5);
  });

  test('omitted sections stay null in the envelope', () {
    final data = ExportData(
      dbVersion: 5,
      exportedAt: 1,
      customSets: [CustomSet('only', ['AB'])],
    );
    final json = data.toJson()['sections'] as Map;
    expect(json.containsKey('recordedTimes'), isFalse);
    expect(json.containsKey('settings'), isFalse);
    expect(json.containsKey('customSets'), isTrue);

    final parsed = ExportData.parse(jsonEncode(data.toJson()));
    expect(parsed.recordedTimes, isNull);
    expect(parsed.settings, isNull);
    expect(parsed.customSets, hasLength(1));
  });

  test('recognitionMs is omitted from JSON when null', () {
    final json = RecordedTime('Corner', 'AB', 1234, 5).toJson();
    expect(json.containsKey('recognitionMs'), isFalse);
  });

  test('a v1 file (no recognitionMs) parses the split as null', () {
    final raw = jsonEncode({
      'format': ExportData.kFormat,
      'formatVersion': 1,
      'dbVersion': 5,
      'exportedAt': 1,
      'sections': {
        'recordedTimes': [
          {'algType': 'Corner', 'alg': 'AB', 'resultMs': 1234, 'timestamp': 2}
        ],
      },
    });
    final parsed = ExportData.parse(raw);
    expect(parsed.recordedTimes![0].recognitionMs, isNull);
  });

  test('non-JSON is rejected as invalidFile', () {
    expect(
      () => ExportData.parse('not json at all'),
      throwsA(isA<ImportException>()
          .having((e) => e.type, 'type', ImportErrorType.invalidFile)),
    );
  });

  test('wrong format field is rejected as unknownFormat', () {
    final raw = jsonEncode({
      'format': 'something-else',
      'formatVersion': 1,
      'dbVersion': 5,
      'exportedAt': 1,
      'sections': {},
    });
    expect(
      () => ExportData.parse(raw),
      throwsA(isA<ImportException>()
          .having((e) => e.type, 'type', ImportErrorType.unknownFormat)),
    );
  });

  test('newer formatVersion is rejected as unsupportedVersion', () {
    final raw = jsonEncode({
      'format': ExportData.kFormat,
      'formatVersion': ExportData.kCurrentFormatVersion + 1,
      'dbVersion': 5,
      'exportedAt': 1,
      'sections': {},
    });
    expect(
      () => ExportData.parse(raw),
      throwsA(isA<ImportException>()
          .having((e) => e.type, 'type', ImportErrorType.unsupportedVersion)),
    );
  });

  test('unknown keys are ignored, missing sections default', () {
    final raw = jsonEncode({
      'format': ExportData.kFormat,
      'formatVersion': 1,
      'dbVersion': 99,
      'exportedAt': 1,
      'somethingNew': 'ignored',
      'sections': {
        'recordedTimes': [
          {'algType': 'Corner', 'alg': 'AB', 'resultMs': 1, 'timestamp': 2}
        ],
      },
    });
    final parsed = ExportData.parse(raw);
    expect(parsed.dbVersion, 99);
    expect(parsed.recordedTimes, hasLength(1));
    expect(parsed.customSets, isNull);
    expect(parsed.settings, isNull);
  });
}
