import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'alg_structs.dart';
import 'export_data.dart';
import 'slowest.dart';

const int DB_VERSION = 8;

const String RESULTS = "results";
const String CUSTOM_SETS = "custom_sets";
const String MISTAKES = "mistakes";

class DatabaseManager {
  late Database _database;

  static final DatabaseManager _singleton = DatabaseManager._internal();

  factory DatabaseManager() {
    return _singleton;
  }

  DatabaseManager._internal();

  void createCustomSetsTable(Database db) {
    db.execute('''
        CREATE TABLE $CUSTOM_SETS(
          name TEXT PRIMARY KEY,
          algs TEXT
        )''');
  }

  // History of every recorded time: one row per timed solve. recognitionMs is
  // the recognition part of a smart-cube split (execution = resultMs − it);
  // NULL for press-timed and pre-v7 rows.
  Future<void> _createResultsTable(Database db) async {
    await db.execute('''
          CREATE TABLE $RESULTS(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            algType TEXT,
            alg TEXT,
            resultMs INTEGER,
            recognitionMs INTEGER,
            timestamp INTEGER
          )''');
    await db.execute(
        'CREATE INDEX idx_results_algType_alg ON $RESULTS(algType, alg)');
  }

  // Cases the user got wrong, one row per slip: a wrong pair executed (with the
  // pair the cube saw) or a requeue. Kept apart from the results history, which
  // holds only honest times — a mistake has none.
  Future<void> _createMistakesTable(Database db) async {
    await db.execute('''
          CREATE TABLE $MISTAKES(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            algType TEXT,
            alg TEXT,
            kind TEXT,
            executed TEXT,
            timestamp INTEGER
          )''');
    await db.execute(
        'CREATE INDEX idx_mistakes_algType_alg ON $MISTAKES(algType, alg)');
  }

  Future<void> _createDb(Database db, int version) async {
    await _createResultsTable(db);
    createCustomSetsTable(db);
    await _createMistakesTable(db);
  }

  Future<void> _upgradeDb(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      createCustomSetsTable(db);
    }
    if (oldVersion < 4) {
      // Old results were a single latest-time-per-case row with no timestamp.
      // Drop them and start the per-attempt history fresh.
      await db.execute('DROP TABLE IF EXISTS $RESULTS');
      await _createResultsTable(db);
    }
    if (oldVersion < 5) {
      await db.execute('DELETE FROM $RESULTS');
    }
    if (oldVersion < 6) {
      // Time race no longer tracks a cycle; results now drive selection.
      await db.execute('DROP TABLE IF EXISTS executed_time_race_algs');
    }
    if (oldVersion < 7) {
      // Carry the smart-cube recognition split; existing rows keep their totals
      // and get a NULL recognition (no split detail).
      await db
          .execute('ALTER TABLE $RESULTS ADD COLUMN recognitionMs INTEGER');
    }
    if (oldVersion < 8) {
      await _createMistakesTable(db);
    }
  }

  bool isUsingDatabase() {
    return true;
    //return !kIsWeb; // Default SQLite not supported in web. Now works with https://pub.dev/packages/sqflite_common_ffi_web
  }

  void initDatabase({Function? onReady}) async {
    if (!isUsingDatabase()) {
      onReady?.call();
      return;
    }

    WidgetsFlutterBinding.ensureInitialized();
    if (kIsWeb || Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
    }

    String path = "";
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    } else {
      databaseFactory = databaseFactoryFfi;
      final Directory documentsDirectory =
          await getApplicationDocumentsDirectory();
      await documentsDirectory.create(recursive: true);
      path = documentsDirectory.path;
    }

    _database = await openDatabase(
      join(path, 'trainer.db'),
      onCreate: (db, version) => _createDb(db, version),
      onUpgrade: (db, oldVersion, newVersion) =>
          _upgradeDb(db, oldVersion, newVersion),
      version: DB_VERSION,
    );

    onReady?.call();
  }

  void insertResult(AlgType algType, String alg, int resultMs,
      {int? timestamp, int? recognitionMs}) async {
    if (!isUsingDatabase()) {
      return;
    }

    Map<String, Object?> map = {
      'algType': algType.name,
      'alg': alg,
      'resultMs': resultMs,
      'recognitionMs': recognitionMs,
      'timestamp': timestamp ?? DateTime.now().millisecondsSinceEpoch,
    };
    await _database.insert(RESULTS, map);
  }

  void deleteRecordedResult(
      AlgType algType, String alg, int resultMs, int timestamp) async {
    if (!isUsingDatabase()) {
      return;
    }

    await _database.delete(
      RESULTS,
      where: "algType = ? AND alg = ? AND resultMs = ? AND timestamp = ?",
      whereArgs: [algType.name, alg, resultMs, timestamp],
    );
  }

  Future<List<AlgStats>> getAlgStats(AlgType algType, {int? sinceMs}) async {
    if (!isUsingDatabase()) {
      return List.empty();
    }

    String where = "algType = ?";
    List<Object> whereArgs = [algType.name];
    if (sinceMs != null) {
      where += " AND timestamp >= ?";
      whereArgs.add(sinceMs);
    }

    // AVG/COUNT ignore NULLs, so the split averages cover only smart-cube rows;
    // splitCount says how many rows carry a recognition/execution split.
    final List<Map<String, Object?>> rows = await _database.rawQuery(
      'SELECT alg, COUNT(*) AS count, MIN(resultMs) AS minMs, '
      'MAX(resultMs) AS maxMs, AVG(resultMs) AS avgMs, '
      'AVG(recognitionMs) AS avgRecognitionMs, '
      'AVG(resultMs - recognitionMs) AS avgExecutionMs, '
      'COUNT(recognitionMs) AS splitCount '
      'FROM $RESULTS WHERE $where GROUP BY alg',
      whereArgs,
    );

    return [
      for (final row in rows) AlgStats.fromMap(row),
    ];
  }

  // Individual recorded attempts for one alg, most recent first.
  Future<List<AlgResult>> getAlgResults(AlgType algType, String alg,
      {int? sinceMs}) async {
    if (!isUsingDatabase()) {
      return List.empty();
    }

    String where = "algType = ? AND alg = ?";
    List<Object> whereArgs = [algType.name, alg];
    if (sinceMs != null) {
      where += " AND timestamp >= ?";
      whereArgs.add(sinceMs);
    }

    final List<Map<String, Object?>> rows = await _database.query(
      RESULTS,
      columns: ['id', 'resultMs', 'recognitionMs', 'timestamp'],
      where: where,
      whereArgs: whereArgs,
      orderBy: "timestamp DESC, id DESC",
    );

    return [
      for (final row in rows) AlgResult.fromMap(row),
    ];
  }

  void deleteResult(int id) async {
    if (!isUsingDatabase()) {
      return;
    }

    await _database.delete(RESULTS, where: "id = ?", whereArgs: [id]);
  }

  void clearAllResults() async {
    if (!isUsingDatabase()) {
      return;
    }

    await _database.delete(RESULTS);
  }

  // Recorded-result count per alg for a type, keyed by alg. Drives time-race equalization
  Future<Map<String, int>> getAlgCounts(AlgType algType) async {
    if (!isUsingDatabase()) {
      return {};
    }

    final List<Map<String, Object?>> rows = await _database.rawQuery(
      'SELECT alg, COUNT(*) AS count FROM $RESULTS '
      'WHERE algType = ? GROUP BY alg',
      [algType.name],
    );

    return {
      for (final row in rows)
        row['alg'] as String: (row['count'] as num).toInt(),
    };
  }

  // Whether any solve has ever been recorded (any type). Gates "Slowest" mode.
  Future<bool> hasAnyRecordedTimes() async {
    if (!isUsingDatabase()) {
      return false;
    }

    final rows = await _database.rawQuery('SELECT 1 FROM $RESULTS LIMIT 1');
    return rows.isNotEmpty;
  }

  // Cases ranked by the average of their most recent [window] solves, slowest first
  Future<List<SlowestAlg>> getSlowestAlgs(AlgType algType,
      {int window = 3}) async {
    if (!isUsingDatabase()) {
      return List.empty();
    }

    final List<Map<String, Object?>> rows = await _database.query(
      RESULTS,
      columns: ['alg', 'resultMs'],
      where: "algType = ?",
      whereArgs: [algType.name],
      orderBy: "timestamp DESC, id DESC",
    );

    return computeRecentAverages(
      [
        for (final row in rows)
          (alg: row['alg'] as String, resultMs: (row['resultMs'] as num).toInt())
      ],
      window,
    );
  }

  // Mistakes. Returns the new row's id so a later slip on the same case in the
  // same run can refine it (see [updateMistake]) instead of adding a row.
  Future<int?> insertMistake(AlgType algType, String alg, AlgMistakeKind kind,
      {String? executed, int? timestamp}) async {
    if (!isUsingDatabase()) {
      return null;
    }

    return await _database.insert(MISTAKES, {
      'algType': algType.name,
      'alg': alg,
      'kind': kind.name,
      'executed': executed,
      'timestamp': timestamp ?? DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateMistake(int id, AlgMistakeKind kind,
      {String? executed}) async {
    if (!isUsingDatabase()) {
      return;
    }

    await _database.update(
      MISTAKES,
      {'kind': kind.name, 'executed': executed},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  // Whether any mistake has ever been recorded (any type). Gates "Slowest" mode
  // alongside the recorded times, since errors alone are enough to drill.
  Future<bool> hasAnyMistakes() async {
    if (!isUsingDatabase()) {
      return false;
    }

    final rows = await _database.rawQuery('SELECT 1 FROM $MISTAKES LIMIT 1');
    return rows.isNotEmpty;
  }

  // Cases ranked by how often they went wrong, most-failed first.
  Future<List<FailedAlg>> getMostFailedAlgs(AlgType algType) async {
    if (!isUsingDatabase()) {
      return List.empty();
    }

    final List<Map<String, Object?>> rows = await _database.rawQuery(
      'SELECT alg, COUNT(*) AS errorCount FROM $MISTAKES WHERE algType = ? '
      'GROUP BY alg ORDER BY errorCount DESC',
      [algType.name],
    );

    return [
      for (final row in rows)
        FailedAlg(row['alg'] as String, (row['errorCount'] as num).toInt()),
    ];
  }

  // Every recorded mistake, for export.
  Future<List<RecordedMistake>> getAllRecordedMistakes() async {
    if (!isUsingDatabase()) {
      return List.empty();
    }

    final List<Map<String, Object?>> rows = await _database.query(
      MISTAKES,
      columns: ['algType', 'alg', 'kind', 'executed', 'timestamp'],
    );

    return [
      for (final row in rows)
        RecordedMistake(
          row['algType'] as String,
          row['alg'] as String,
          row['kind'] as String,
          (row['timestamp'] as num).toInt(),
          executed: row['executed'] as String?,
        ),
    ];
  }

  // Insert imported mistakes, de-duping by (algType, alg, timestamp) against
  // existing rows and within the input. Returns rows inserted.
  Future<int> importRecordedMistakes(List<RecordedMistake> mistakes) async {
    if (!isUsingDatabase() || mistakes.isEmpty) {
      return 0;
    }

    final List<Map<String, Object?>> existing = await _database.query(
      MISTAKES,
      columns: ['algType', 'alg', 'timestamp'],
    );
    final Set<String> seen = {
      for (final row in existing)
        '${row['algType']}|${row['alg']}|${row['timestamp']}',
    };

    final batch = _database.batch();
    int inserted = 0;
    for (final m in mistakes) {
      if (seen.add('${m.algType}|${m.alg}|${m.timestamp}')) {
        batch.insert(MISTAKES, {
          'algType': m.algType,
          'alg': m.alg,
          'kind': m.kind,
          'executed': m.executed,
          'timestamp': m.timestamp,
        });
        inserted++;
      }
    }
    await batch.commit(noResult: true);
    return inserted;
  }

  // Custom sets
  void insertCustomSet(CustomSet customSet) async {
    if (!isUsingDatabase()) {
      return;
    }

    await _database.insert(
      CUSTOM_SETS,
      customSet.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  void updateCustomSet(String oldName, CustomSet customSet) async {
    if (!isUsingDatabase()) {
      return;
    }

    Map<String, Object> values = {
      'name': customSet.name,
      'algs': customSet.algsToString()
    };
    List<Object> whereArgs = [oldName];
    await _database.update(
      CUSTOM_SETS,
      values,
      where: "name = ?",
      whereArgs: whereArgs,
    );
  }

  void deleteCustomSet(String customSetName) async {
    if (!isUsingDatabase()) {
      return;
    }

    List<Object> whereArgs = [customSetName];
    await _database.delete(
      CUSTOM_SETS,
      where: "name = ?",
      whereArgs: whereArgs,
    );
  }

  Future<List<CustomSet>> getCustomSets() async {
    if (!isUsingDatabase()) {
      return List.empty();
    }

    final List<Map<String, Object?>> sets = await _database.query(CUSTOM_SETS);

    return [
      for (final entry in sets) CustomSet.fromMap(entry),
    ];
  }

  // Every recorded solve, for export.
  Future<List<RecordedTime>> getAllRecordedTimes() async {
    if (!isUsingDatabase()) {
      return List.empty();
    }

    final List<Map<String, Object?>> rows = await _database.query(
      RESULTS,
      columns: ['algType', 'alg', 'resultMs', 'recognitionMs', 'timestamp'],
    );

    return [
      for (final row in rows)
        RecordedTime(
          row['algType'] as String,
          row['alg'] as String,
          (row['resultMs'] as num).toInt(),
          (row['timestamp'] as num).toInt(),
          recognitionMs: (row['recognitionMs'] as num?)?.toInt(),
        ),
    ];
  }

  String _recordedTimeKey(
          Object? algType, Object? alg, Object? timestamp, Object? resultMs) =>
      '$algType|$alg|$timestamp|$resultMs';

  // Insert imported recorded times, de-duping by (algType, alg, timestamp,
  // resultMs) against both existing rows and duplicates within the input.
  // Ids are never imported — SQLite assigns fresh ones. Returns rows inserted.
  Future<int> importRecordedTimes(List<RecordedTime> times) async {
    if (!isUsingDatabase() || times.isEmpty) {
      return 0;
    }

    final List<Map<String, Object?>> existing = await _database.query(
      RESULTS,
      columns: ['algType', 'alg', 'timestamp', 'resultMs'],
    );
    final Set<String> seen = {
      for (final row in existing)
        _recordedTimeKey(
            row['algType'], row['alg'], row['timestamp'], row['resultMs']),
    };

    final batch = _database.batch();
    int inserted = 0;
    for (final t in times) {
      final key = _recordedTimeKey(t.algType, t.alg, t.timestamp, t.resultMs);
      if (seen.add(key)) {
        batch.insert(RESULTS, {
          'algType': t.algType,
          'alg': t.alg,
          'resultMs': t.resultMs,
          'recognitionMs': t.recognitionMs,
          'timestamp': t.timestamp,
        });
        inserted++;
      }
    }
    await batch.commit(noResult: true);
    return inserted;
  }

  // Insert imported custom sets, de-duping by name: a set whose name already
  // exists locally is skipped (not overwritten). Returns the skipped names.
  Future<List<String>> importCustomSets(List<CustomSet> sets) async {
    if (!isUsingDatabase() || sets.isEmpty) {
      return List.empty();
    }

    final List<Map<String, Object?>> existing =
        await _database.query(CUSTOM_SETS, columns: ['name']);
    final Set<String> names = {
      for (final row in existing) row['name'] as String,
    };

    final batch = _database.batch();
    final List<String> skipped = [];
    for (final set in sets) {
      if (!names.add(set.name)) {
        skipped.add(set.name);
      } else {
        batch.insert(CUSTOM_SETS, set.toMap());
      }
    }
    await batch.commit(noResult: true);
    return skipped;
  }
}
