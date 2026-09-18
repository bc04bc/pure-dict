import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dict/core/db/user_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final dbFactory = databaseFactoryFfi;

  group('UserData & UserDatabase', () {
    late Database db;

    setUp(() async {
      db = await dbFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS user_words (
                word TEXT PRIMARY KEY,
                in_study INTEGER NOT NULL DEFAULT 1,
                query_count INTEGER NOT NULL DEFAULT 1,
                last_queried_at INTEGER NOT NULL,
                srs_stage INTEGER NOT NULL DEFAULT 0,
                next_review_at INTEGER,
                interval_days REAL NOT NULL DEFAULT 0,
                ease_factor REAL NOT NULL DEFAULT 2.5,
                lapse_count INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                is_deleted INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS search_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word TEXT NOT NULL,
                queried_at INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS sync_meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at INTEGER NOT NULL
              )
            ''');
          },
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('migrates legacy SharedPreferences data on first init', () async {
      SharedPreferences.setMockInitialValues({
        'favorites': ['apple', 'book'],
        'search_history': ['apple', 'cat', 'dog'],
      });
      final prefs = await SharedPreferences.getInstance();

      final userData = UserData(db, prefs);
      await userData.init();

      expect(userData.favorites, containsAll(['apple', 'book']));
      expect(userData.history, containsAll(['apple', 'cat', 'dog']));

      final apple = await userData.getUserWord('apple');
      expect(apple, isNotNull);
      expect(apple!.inStudy, isTrue);
      expect(apple.queryCount, 1);

      // Check migration flag
      expect(prefs.getBool('migrated_to_user_db_v1'), isTrue);
    });

    test('auto-captures English words and increments query count on repeated search', () async {
      SharedPreferences.setMockInitialValues({
        'migrated_to_user_db_v1': true,
      });
      final prefs = await SharedPreferences.getInstance();

      final userData = UserData(db, prefs);
      await userData.init();
      expect(userData.studyEnabled, isTrue);

      // Query "read" 1st time
      await userData.addHistory('read');
      expect(userData.isFavorite('read'), isTrue);
      expect(userData.history.first, 'read');

      var entry = await userData.getUserWord('read');
      expect(entry, isNotNull);
      expect(entry!.queryCount, 1);
      final firstQueryTime = entry.lastQueriedAt;

      // Query "read" 2nd time
      await Future.delayed(const Duration(milliseconds: 10));
      await userData.addHistory('read');

      entry = await userData.getUserWord('read');
      expect(entry, isNotNull);
      expect(entry!.queryCount, 2);
      expect(entry.lastQueriedAt.isAfter(firstQueryTime) ||
          entry.lastQueriedAt == firstQueryTime, isTrue);
    });

    test('does not auto-capture Chinese queries into study library', () async {
      SharedPreferences.setMockInitialValues({
        'migrated_to_user_db_v1': true,
      });
      final prefs = await SharedPreferences.getInstance();

      final userData = UserData(db, prefs);
      await userData.init();

      // Chinese query
      await userData.addHistory('苹果');
      expect(userData.history, contains('苹果'));
      expect(userData.isFavorite('苹果'), isFalse);

      final entry = await userData.getUserWord('苹果');
      expect(entry, isNull);
    });

    test('removeFromStudy marks word with tombstone', () async {
      SharedPreferences.setMockInitialValues({
        'migrated_to_user_db_v1': true,
      });
      final prefs = await SharedPreferences.getInstance();

      final userData = UserData(db, prefs);
      await userData.init();

      await userData.addHistory('galaxy');
      expect(userData.isFavorite('galaxy'), isTrue);

      // Remove from study
      await userData.removeFromStudy('galaxy');
      expect(userData.isFavorite('galaxy'), isFalse);

      final entry = await userData.getUserWord('galaxy');
      expect(entry, isNotNull);
      expect(entry!.inStudy, isFalse);
      expect(entry.isDeleted, isTrue);
    });

    test('disabling study mode stops auto-capturing', () async {
      SharedPreferences.setMockInitialValues({
        'migrated_to_user_db_v1': true,
      });
      final prefs = await SharedPreferences.getInstance();

      final userData = UserData(db, prefs);
      await userData.init();
      await userData.setStudyEnabled(false);

      await userData.addHistory('nebula');
      expect(userData.history, contains('nebula'));
      expect(userData.isFavorite('nebula'), isFalse);

      final entry = await userData.getUserWord('nebula');
      expect(entry, isNull);
    });
  });
}
