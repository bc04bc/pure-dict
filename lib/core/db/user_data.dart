import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/study_entry.dart';
import 'user_database.dart';

class UserData {
  UserData(this._db, this._prefs);

  final Database _db;
  final SharedPreferences _prefs;

  static const _migratedKey = 'migrated_to_user_db_v1';
  static const _studyEnabledKey = 'study_mode_enabled';
  static const _dailyReviewQuotaKey = 'study_daily_review_quota';
  static const _maxHistory = 50;

  static final _validEnglishWord =
      RegExp(r"^[a-zA-Z]+(?:['’-][a-zA-Z]+)*$");

  final List<String> _historyCache = [];
  final Set<String> _favoritesCache = {};

  List<String> get history => List.unmodifiable(_historyCache);
  List<String> get favorites => List.unmodifiable(_favoritesCache.toList());

  bool get studyEnabled => _prefs.getBool(_studyEnabledKey) ?? true;

  int get dailyReviewQuota => _prefs.getInt(_dailyReviewQuotaKey) ?? 20;

  Future<void> setStudyEnabled(bool enabled) async {
    await _prefs.setBool(_studyEnabledKey, enabled);
  }

  Future<void> setDailyReviewQuota(int quota) async {
    await _prefs.setInt(_dailyReviewQuotaKey, quota);
  }

  /// Initializes caches and runs one-time migration from legacy SharedPreferences.
  Future<void> init() async {
    final migrated = _prefs.getBool(_migratedKey) ?? false;
    if (!migrated) {
      await _migrateFromPrefs();
      await _prefs.setBool(_migratedKey, true);
    }
    await reloadCaches();
  }

  Future<void> _migrateFromPrefs() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final legacyFavorites = _prefs.getStringList('favorites') ?? [];
    final legacyHistory = _prefs.getStringList('search_history') ?? [];

    final batch = _db.batch();
    for (final word in legacyFavorites) {
      final trimmed = word.trim();
      if (trimmed.isEmpty) continue;
      batch.insert(
        'user_words',
        {
          'word': trimmed,
          'in_study': 1,
          'query_count': 1,
          'last_queried_at': now,
          'srs_stage': 0,
          'next_review_at': null,
          'interval_days': 0.0,
          'ease_factor': 2.5,
          'lapse_count': 0,
          'created_at': now,
          'updated_at': now,
          'is_deleted': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    var ts = now - legacyHistory.length * 1000;
    for (final word in legacyHistory.reversed) {
      final trimmed = word.trim();
      if (trimmed.isEmpty) continue;
      batch.insert(
        'search_history',
        {
          'word': trimmed,
          'queried_at': ts,
        },
      );
      ts += 1000;
    }

    await batch.commit(noResult: true);
  }

  Future<void> reloadCaches() async {
    // Reload history
    final historyRows = await _db.query(
      'search_history',
      columns: ['word'],
      orderBy: 'queried_at DESC',
      limit: _maxHistory,
    );
    _historyCache
      ..clear()
      ..addAll(historyRows.map((r) => r['word'] as String));

    // Reload favorites / active study words
    final favRows = await _db.query(
      'user_words',
      columns: ['word'],
      where: 'in_study = 1 AND is_deleted = 0',
      orderBy: 'updated_at DESC',
    );
    _favoritesCache
      ..clear()
      ..addAll(favRows.map((r) => r['word'] as String));
  }

  Future<void> addHistory(String rawWord, {bool captureStudy = true}) async {
    final word = rawWord.trim();
    if (word.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Update search history table
    await _db.transaction((txn) async {
      await txn.delete('search_history', where: 'word = ?', whereArgs: [word]);
      await txn.insert('search_history', {
        'word': word,
        'queried_at': now,
      });

      // Maintain history cap
      final countResult = await txn.rawQuery(
        'SELECT COUNT(*) as c FROM search_history',
      );
      final count = Sqflite.firstIntValue(countResult) ?? 0;
      if (count > _maxHistory) {
        await txn.rawDelete(
          '''
          DELETE FROM search_history WHERE id IN (
            SELECT id FROM search_history ORDER BY queried_at ASC LIMIT ?
          )
          ''',
          [count - _maxHistory],
        );
      }
    });

    _historyCache.remove(word);
    _historyCache.insert(0, word);
    if (_historyCache.length > _maxHistory) {
      _historyCache.removeRange(_maxHistory, _historyCache.length);
    }

    // 2. Auto-capture into study library if study mode is enabled and is valid English word
    if (captureStudy && studyEnabled && _validEnglishWord.hasMatch(word)) {
      await recordStudyQuery(word, now: now);
    }
  }

  /// Records or increments query count for a word in `user_words`.
  Future<void> recordStudyQuery(String word, {int? now}) async {
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await _db.query(
      'user_words',
      where: 'word = ? COLLATE NOCASE',
      whereArgs: [word],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final current = UserWordEntry.fromRow(existing.first);
      // Increment query count and reactivate if previously marked not in study
      await _db.update(
        'user_words',
        {
          'query_count': current.queryCount + 1,
          'last_queried_at': timestamp,
          'updated_at': timestamp,
          'in_study': 1,
          'is_deleted': 0,
        },
        where: 'word = ? COLLATE NOCASE',
        whereArgs: [word],
      );
    } else {
      await _db.insert(
        'user_words',
        {
          'word': word,
          'in_study': 1,
          'query_count': 1,
          'last_queried_at': timestamp,
          'srs_stage': 0,
          'next_review_at': null,
          'interval_days': 0.0,
          'ease_factor': 2.5,
          'lapse_count': 0,
          'created_at': timestamp,
          'updated_at': timestamp,
          'is_deleted': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    _favoritesCache.add(word);
  }

  Future<void> clearHistory() async {
    await _db.delete('search_history');
    _historyCache.clear();
  }

  Future<bool> toggleFavorite(String rawWord) async {
    final word = rawWord.trim();
    if (word.isEmpty) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final isFav = isFavorite(word);

    if (isFav) {
      await _db.update(
        'user_words',
        {
          'in_study': 0,
          'is_deleted': 1,
          'updated_at': now,
        },
        where: 'word = ? COLLATE NOCASE',
        whereArgs: [word],
      );
      _favoritesCache.remove(word);
      return false;
    } else {
      await recordStudyQuery(word, now: now);
      _favoritesCache.add(word);
      return true;
    }
  }

  /// Removes word from active study deck (tombstone).
  Future<void> removeFromStudy(String rawWord) async {
    final word = rawWord.trim();
    if (word.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'user_words',
      {
        'in_study': 0,
        'is_deleted': 1,
        'updated_at': now,
      },
      where: 'word = ? COLLATE NOCASE',
      whereArgs: [word],
    );
    _favoritesCache.remove(word);
  }

  bool isFavorite(String word) => _favoritesCache.contains(word);

  Future<void> clearFavorites() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'user_words',
      {
        'in_study': 0,
        'is_deleted': 1,
        'updated_at': now,
      },
      where: 'in_study = 1 AND is_deleted = 0',
    );
    _favoritesCache.clear();
  }

  Future<UserWordEntry?> getUserWord(String word) async {
    final rows = await _db.query(
      'user_words',
      where: 'word = ? COLLATE NOCASE',
      whereArgs: [word.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserWordEntry.fromRow(rows.first);
  }

  Future<List<UserWordEntry>> getActiveStudyEntries() async {
    final rows = await _db.query(
      'user_words',
      where: 'in_study = 1 AND is_deleted = 0',
      orderBy: 'updated_at DESC',
    );
    return rows.map(UserWordEntry.fromRow).toList();
  }

  Future<void> saveUserWord(UserWordEntry entry) async {
    await _db.insert(
      'user_words',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (entry.inStudy && !entry.isDeleted) {
      _favoritesCache.add(entry.word);
    } else {
      _favoritesCache.remove(entry.word);
    }
  }
}

final userDataProvider = FutureProvider<UserData>((ref) async {
  final db = await UserDatabase.instance;
  final prefs = await SharedPreferences.getInstance();
  final user = UserData(db, prefs);
  await user.init();
  return user;
});

final historyProvider = FutureProvider<List<String>>((ref) async {
  final user = await ref.watch(userDataProvider.future);
  return user.history;
});

final favoritesProvider = FutureProvider<List<String>>((ref) async {
  final user = await ref.watch(userDataProvider.future);
  return user.favorites;
});
