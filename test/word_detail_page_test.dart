import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dict/core/db/dict_repository.dart';
import 'package:dict/core/db/user_data.dart';
import 'package:dict/core/models/word_entry.dart';
import 'package:dict/core/network/online_dict.dart';
import 'package:dict/features/word/word_detail_page.dart';

/// In-memory repository double: exact lookups plus a tiny prefix matcher,
/// enough to exercise the re-lookup search flow without a real SQLite db.
class FakeDictRepository implements DictRepository {
  static const _entries = [
    WordEntry(word: 'apple', phonetic: 'ˈæpl', translation: 'n. 苹果'),
    WordEntry(word: 'banana', phonetic: 'bəˈnɑːnə', translation: 'n. 香蕉'),
    WordEntry(word: 'band', phonetic: 'bænd', translation: 'n. 乐队'),
  ];

  @override
  Future<WordEntry?> lookup(String word) async {
    for (final e in _entries) {
      if (e.word == word || e.word.toLowerCase() == word.toLowerCase()) {
        return e;
      }
    }
    return null;
  }

  @override
  Future<List<WordEntry>> suggestions(String prefix, {int limit = 12}) async {
    final query = prefix.trim().toLowerCase();
    return _entries.where((e) => e.word.startsWith(query)).take(limit).toList();
  }
}

/// SharedPreferences double storing history/favorites in memory.
class FakeUserData implements UserData {
  final List<String> _history = [];
  final List<String> _favorites = [];

  @override
  List<String> get history => List.unmodifiable(_history);

  @override
  List<String> get favorites => List.unmodifiable(_favorites);

  @override
  Future<void> addHistory(String word) async {
    _history.remove(word);
    _history.insert(0, word);
  }

  @override
  Future<void> clearHistory() async => _history.clear();

  @override
  Future<void> clearFavorites() async => _favorites.clear();

  @override
  bool isFavorite(String word) => _favorites.contains(word);

  @override
  Future<bool> toggleFavorite(String word) async {
    if (_favorites.remove(word)) return false;
    _favorites.insert(0, word);
    return true;
  }
}

Widget _buildApp() {
  return ProviderScope(
    overrides: [
      dictRepositoryProvider.overrideWith((ref) async => FakeDictRepository()),
      userDataProvider.overrideWith((ref) async => FakeUserData()),
      onlineLookupProvider.overrideWith((ref, word) async => null),
      onlineZhLookupProvider.overrideWith((ref, word) async => null),
    ],
    child: const MaterialApp(home: WordDetailPage(word: 'apple')),
  );
}

void main() {
  testWidgets('detail page shows re-lookup button and opens search', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsWidgets);
    expect(find.byTooltip('重新查词'), findsOneWidget);

    await tester.tap(find.byTooltip('重新查词'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('输入英文或中文开始搜索'), findsOneWidget);
  });

  testWidgets('re-lookup switches the detail page to the picked word', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重新查词'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ban');
    // Let the 250 ms suggestion debounce fire, then resolve the future.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('banana'), findsOneWidget); // suggestion row

    await tester.tap(find.text('banana'));
    await tester.pumpAndSettle();

    // Page switched in place: title + body show the new word, old one gone.
    expect(find.text('banana'), findsNWidgets(2));
    expect(find.text('香蕉'), findsWidgets);
    expect(find.text('apple'), findsNothing);
  });

  testWidgets('submitting the query looks up the raw input word', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重新查词'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'band');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // Press the keyboard search action to submit the query directly.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('band'), findsWidgets);
    expect(find.text('乐队'), findsWidgets);
  });

  testWidgets('cancelling the search keeps the current word', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重新查词'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsWidgets);
    expect(find.text('banana'), findsNothing);
  });
}
