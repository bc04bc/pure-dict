import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/db/dict_repository.dart';
import '../../core/db/user_data.dart';
import '../../core/models/word_entry.dart';

final wordOfDayProvider = FutureProvider<WordEntry?>((ref) async {
  final db = await AppDatabase.instance;
  final now = DateTime.now();
  final days = now.difference(DateTime(2026, 1, 1)).inDays.abs();
  final count = (await db.rawQuery(
    'SELECT COUNT(*) AS c FROM words WHERE frq > 0',
  ))
      .first['c'] as int;
  if (count == 0) return null;
  final offset = (days * 7919) % count;
  final rows = await db.rawQuery(
    'SELECT word, phonetic, translation, frq, bnc FROM words '
    'WHERE frq > 0 ORDER BY frq LIMIT 1 OFFSET ?',
    [offset],
  );
  return rows.isEmpty ? null : WordEntry.fromRow(rows.first);
});

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<WordEntry> _suggestions = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _suggestions = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final repo = await ref.read(dictRepositoryProvider.future);
      final results = await repo.suggestions(query);
      if (!mounted) return;
      setState(() {
        _searching = true;
        _suggestions = results;
      });
    });
  }

  void _openWord(String word) {
    _controller.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = false;
      _suggestions = const [];
    });
    ref.invalidate(historyProvider);
    context.push('/word/$word');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '词典',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) {
                final query = value.trim();
                if (query.isNotEmpty) _openWord(query);
              },
              decoration: InputDecoration(
                hintText: '输入英文或中文…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searching && _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _searching
                ? _SuggestionList(
                    suggestions: _suggestions,
                    onTap: _openWord,
                  )
                : _HomeContent(onOpenWord: _openWord),
          ),
        ],
      ),
    );
  }
}

class _SuggestionList extends ConsumerWidget {
  const _SuggestionList({required this.suggestions, required this.onTap});

  final List<WordEntry> suggestions;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (suggestions.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的词',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: suggestions.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) {
        final entry = suggestions[index];
        final isChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(entry.word);
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: Icon(
            isChinese ? Icons.translate_rounded : Icons.menu_book_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            entry.word,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: entry.translation != null &&
                  entry.translation!.isNotEmpty
              ? Text(
                  entry.translation!.split('\n').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => onTap(entry.word),
        );
      },
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({required this.onOpenWord});

  final void Function(String) onOpenWord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wordOfDay = ref.watch(wordOfDayProvider);
    final history = ref.watch(historyProvider);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        wordOfDay.when(
          loading: () => const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (entry) {
            if (entry == null) return const SizedBox.shrink();
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onOpenWord(entry.word),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.wb_sunny_outlined,
                            size: 18,
                            color: scheme.tertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '今日一词',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.tertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              entry.word,
                              style: theme.textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (entry.phonetic != null)
                            Text(
                              '${entry.phonetic}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.translation ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '最近浏览',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (history.valueOrNull?.isNotEmpty ?? false)
              TextButton(
                onPressed: () async {
                  final user = await ref.read(userDataProvider.future);
                  await user.clearHistory();
                  ref.invalidate(historyProvider);
                },
                child: const Text('清空'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        history.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) {
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 48,
                      color: scheme.outlineVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '暂无浏览记录',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.outline),
                    ),
                  ],
                ),
              );
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: list
                  .map(
                    (word) => ActionChip(
                      label: Text(word),
                      onPressed: () => onOpenWord(word),
                      avatar: Icon(
                        Icons.history_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}
