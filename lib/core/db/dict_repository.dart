import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../models/word_entry.dart';
import 'app_database.dart';

class DictRepository {
  DictRepository(this._db);

  final Database _db;

  static final _cjkRe = RegExp(r'[\u4e00-\u9fff]');

  Future<WordEntry?> lookup(String word) async {
    final query = word.trim();
    if (query.isEmpty) return null;

    var rows = await _db.query(
      'words',
      where: 'word = ?',
      whereArgs: [query],
      limit: 1,
    );
    if (rows.isEmpty) {
      rows = await _db.query(
        'words',
        where: 'word = ? COLLATE NOCASE',
        whereArgs: [query],
        limit: 1,
      );
    }
    if (rows.isEmpty) return null;
    return WordEntry.fromRow(rows.first);
  }

  Future<List<WordEntry>> suggestions(String prefix, {int limit = 12}) async {
    final query = prefix.trim().toLowerCase();
    if (query.isEmpty) return const [];

    List<Map<String, Object?>> rows;
    if (_cjkRe.hasMatch(query)) {
      rows = await _searchChinese(query, limit);
    } else {
      rows = await _db.query(
        'words',
        columns: ['word', 'phonetic', 'translation', 'frq', 'bnc'],
        where: 'word LIKE ? AND length(word) <= ?',
        whereArgs: ['$query%', (query.length + 12).toString()],
        orderBy: 'CASE WHEN frq > 0 THEN frq ELSE 1000000 END ASC, word ASC',
        limit: limit,
      );
    }
    return rows.map(WordEntry.fromRow).toList();
  }

  Future<List<Map<String, Object?>>> _searchChinese(
    String query,
    int limit,
  ) async {
    final grams = <String>[];
    for (var i = 0; i < query.length - 1; i++) {
      grams.add(query.substring(i, i + 2));
    }
    if (query.length == 1) grams.add(query);
    if (grams.isEmpty) return const [];

    final placeholders = List.filled(grams.length, '?').join(',');
    return _db.rawQuery(
      '''
      SELECT w.word, w.phonetic, w.translation, w.frq, w.bnc
      FROM zh_index z
      JOIN words w ON w.word = z.word
      WHERE z.seg IN ($placeholders)
      GROUP BY w.word
      ORDER BY
        CASE WHEN w.translation LIKE ? THEN 0 ELSE 1 END,
        COUNT(*) DESC,
        CASE WHEN w.frq > 0 THEN w.frq ELSE 1000000 END ASC
      LIMIT ?
      ''',
      [...grams, '%$query%', limit],
    );
  }
}

final dictRepositoryProvider = FutureProvider<DictRepository>((ref) async {
  final db = await AppDatabase.instance;
  return DictRepository(db);
});
