import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'alg_structs.dart';
import 'export_data.dart';

const int DB_VERSION = 6;

const String RESULTS = "results";
const String CUSTOM_SETS = "custom_sets";

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

  // History of every recorded time: one row per timed solve.
  Future<void> _createResultsTable(Database db) async {
    await db.execute('''
          CREATE TABLE $RESULTS(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            algType TEXT,
            alg TEXT,
            resultMs INTEGER,
            timestamp INTEGER
          )''');
    await db.execute(
        'CREATE INDEX idx_results_algType_alg ON $RESULTS(algType, alg)');
  }

  Future<void> _createDb(Database db, int version) async {
    await _createResultsTable(db);
    createCustomSetsTable(db);
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

  void insertResult(AlgType algType, String alg, int resultMs) async {
    if (!isUsingDatabase()) {
      return;
    }

    Map<String, Object?> map = {
      'algType': algType.name,
      'alg': alg,
      'resultMs': resultMs,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await _database.insert(RESULTS, map);
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

    final List<Map<String, Object?>> rows = await _database.rawQuery(
      'SELECT alg, COUNT(*) AS count, MIN(resultMs) AS minMs, '
      'MAX(resultMs) AS maxMs, AVG(resultMs) AS avgMs '
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
      columns: ['id', 'resultMs', 'timestamp'],
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
      columns: ['algType', 'alg', 'resultMs', 'timestamp'],
    );

    return [
      for (final row in rows)
        RecordedTime(
          row['algType'] as String,
          row['alg'] as String,
          (row['resultMs'] as num).toInt(),
          (row['timestamp'] as num).toInt(),
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
