import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'alg_structs.dart';

const int DB_VERSION = 5;

const String RESULTS = "results";
const String EXECUTED_TIME_RACE_ALGS = "executed_time_race_algs";
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
    await db.execute('''
          CREATE TABLE $EXECUTED_TIME_RACE_ALGS(
            algType TEXT,
            alg TEXT,
            PRIMARY KEY(algType, alg)
          )''');
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
    await _database.delete(EXECUTED_TIME_RACE_ALGS);
  }

  void insertExecutedTimeRaceAlg(AlgType algType, String alg) async {
    if (!isUsingDatabase()) {
      return;
    }

    Map<String, Object?> map = {
      'algType': algType.name,
      'alg': alg,
    };
    await _database.insert(
      EXECUTED_TIME_RACE_ALGS,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> getExecutedTimeRaceAlgs(AlgType algType) async {
    if (!isUsingDatabase()) {
      return List.empty();
    }

    List<Object> whereArgs = [algType.name];
    final List<Map<String, Object?>> algs = await _database.query(
        EXECUTED_TIME_RACE_ALGS,
        where: "algType = ?",
        whereArgs: whereArgs);

    return [
      for (final entry in algs) entry['alg'] as String,
    ];
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

  void resetExecutedTimeRaceAlgs() {
    if (!isUsingDatabase()) {
      return;
    }

    _database.delete(EXECUTED_TIME_RACE_ALGS);
  }

  // Read-only backup: checkpoints the WAL then copies the live DB to a temp
  // file, leaving the original untouched. Returns the copy's path.
  Future<String> exportDatabaseCopy() async {
    await _database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final Directory tempDir = await getTemporaryDirectory();
    final String outPath = join(tempDir.path, 'trainer_backup.db');
    await File(_database.path).copy(outPath);
    return outPath;
  }
}
