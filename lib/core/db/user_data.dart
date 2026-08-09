import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserData {
  UserData(this._prefs);

  static const _historyKey = 'search_history';
  static const _favoritesKey = 'favorites';
  static const _maxHistory = 50;

  final SharedPreferences _prefs;

  List<String> get history => _prefs.getStringList(_historyKey) ?? [];
  List<String> get favorites => _prefs.getStringList(_favoritesKey) ?? [];

  Future<void> addHistory(String word) async {
    final list = List<String>.from(history);
    list.remove(word);
    list.insert(0, word);
    if (list.length > _maxHistory) {
      list.removeRange(_maxHistory, list.length);
    }
    await _prefs.setStringList(_historyKey, list);
  }

  Future<void> clearHistory() => _prefs.remove(_historyKey);

  Future<bool> toggleFavorite(String word) async {
    final list = List<String>.from(favorites);
    var added = false;
    if (list.remove(word)) {
      added = false;
    } else {
      list.insert(0, word);
      added = true;
    }
    await _prefs.setStringList(_favoritesKey, list);
    return added;
  }

  bool isFavorite(String word) => favorites.contains(word);

  Future<void> clearFavorites() => _prefs.remove(_favoritesKey);
}

final userDataProvider = FutureProvider<UserData>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return UserData(prefs);
});

final historyProvider = FutureProvider<List<String>>((ref) async {
  final user = await ref.watch(userDataProvider.future);
  return user.history;
});

final favoritesProvider = FutureProvider<List<String>>((ref) async {
  final user = await ref.watch(userDataProvider.future);
  return user.favorites;
});
