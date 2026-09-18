import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Manages the mutable user database (`user.db`), completely separate from the
/// bundled read-only dictionary (`dict.sqlite`).
///
/// Stores search history, vocabulary study records (SRS progress, query
/// frequency, timestamps), sync metadata, and tombstones for incremental sync.
class UserDatabase {
  UserDatabase._();

  static const _dbName = 'user.db';
  static const _dbVersion = 1;
  static Database? _db;

  /// Custom database instance for unit tests (e.g. in-memory or custom path).
  static Database? testDatabase;

  static Future<Database> get instance async {
    if (testDatabase != null) return testDatabase!;
    if (_db != null && _db!.isOpen) return _db!;

    final dir = await getApplicationSupportDirectory();
    final target = p.join(dir.path, _dbName);
    _db = await openDatabase(
      target,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  static Future<void> _onCreate(Database db, int version) async {
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
      CREATE INDEX IF NOT EXISTS idx_user_words_updated_at 
      ON user_words(updated_at)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_user_words_study 
      ON user_words(in_study, is_deleted)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS search_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL,
        queried_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_search_history_word 
      ON search_history(word)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_search_history_queried 
      ON search_history(queried_at DESC)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Schema migrations for future versions.
  }

  static Future<void> close() async {
    if (testDatabase != null) {
      await testDatabase!.close();
      testDatabase = null;
    }
    await _db?.close();
    _db = null;
  }
}
