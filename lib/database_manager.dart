import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'alg_structs.dart';

const int DB_VERSION = 3;

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

  void _createDb(Database db, int version) {
    db.execute('''
          CREATE TABLE $RESULTS(
            algType TEXT,
            alg TEXT,
            resultMs INTEGER,
            PRIMARY KEY(algType, alg)
          )''');
    db.execute('''
          CREATE TABLE $EXECUTED_TIME_RACE_ALGS(
            algType TEXT,
            alg TEXT,
            PRIMARY KEY(algType, alg)
          )''');
    createCustomSetsTable(db);
  }

  void _upgradeDb(Database db, int oldVersion, int newVersion) {
    if (oldVersion < 3) {
      createCustomSetsTable(db);
    }
  }

  void initDatabase({Function? onReady}) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
    }
    databaseFactory = databaseFactoryFfi;

    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    await documentsDirectory.create(recursive: true);
    _database = await openDatabase(
      join(documentsDirectory.path, 'trainer.db'),
      onCreate: (db, version) => _createDb(db, version),
      onUpgrade: (db, oldVersion, newVersion) =>
          _upgradeDb(db, oldVersion, newVersion),
      version: DB_VERSION,
    );

    onReady?.call();
  }

  void insertResult(AlgType algType, String alg, int resultMs) async {
    Map<String, Object?> map = {
      'algType': algType.name,
      'alg': alg,
      'resultMs': resultMs,
    };
    await _database.insert(
      RESULTS,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  void insertExecutedTimeRaceAlg(AlgType algType, String alg) async {
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
    await _database.insert(
      CUSTOM_SETS,
      customSet.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CustomSet>> getCustomSets() async {
    final List<Map<String, Object?>> sets = await _database.query(CUSTOM_SETS);

    return [
      for (final entry in sets) CustomSet.fromMap(entry),
    ];
  }

  void resetExecutedTimeRaceAlgs() {
    _database.delete(EXECUTED_TIME_RACE_ALGS);
  }
}
