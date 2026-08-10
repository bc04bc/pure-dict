import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/db/dict_repository.dart';
import '../../core/text/translation_parse.dart';
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
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<WordEntry> _suggestions = const [];
  bool _focused = false;
  bool _hasQuery = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {
      _focused = _focusNode.hasFocus;
      if (!_focused) {
        _debounce?.cancel();
        _hasQuery = false;
        _suggestions = const [];
      }
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _hasQuery = false;
        _suggestions = const [];
      });
      return;
    }
    setState(() => _hasQuery = true);
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final repo = await ref.read(dictRepositoryProvider.future);
      final results = await repo.suggestions(query);
      if (!mounted) return;
      setState(() => _suggestions = results);
    });
  }

  void _openWord(String word) {
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _focused = false;
      _hasQuery = false;
      _suggestions = const [];
    });
    ref.invalidate(historyProvider);
    context.push('/word/$word');
  }

  /// Tapping empty space in the suggestion area dismisses the search layout,
  /// but only when the field is empty (no query in progress).
  void _dismissSearch() {
    if (_hasQuery) return;
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _focused = false;
      _suggestions = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final showSearch = _focused || _hasQuery;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final idleFieldTop = height * 0.36;
            final brandTop = idleFieldTop - 190;
            return Stack(
              children: [
                // 品牌块（图标 + 标题）：贴输入框上方，随布局移动
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOutCubic,
                  top: showSearch ? -240 : brandTop,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: showSearch,
                    child: AnimatedOpacity(
                      opacity: showSearch ? 0 : 1,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _BrandBlock(
                          scheme: Theme.of(context).colorScheme,
                        ),
                      ),
                    ),
                  ),
                ),
                // 今日一词（聚焦时淡出）
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: IgnorePointer(
                    ignoring: showSearch,
                    child: AnimatedOpacity(
                      opacity: showSearch ? 0 : 1,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: _WordOfDayCard(onOpenWord: _openWord),
                    ),
                  ),
                ),
                // 搜索输入框：聚焦时平滑移动到顶部
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOutCubic,
                  top: showSearch ? 12 : idleFieldTop,
                  left: 20,
                  right: 20,
                  child: _SearchField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: _onChanged,
                    onSubmitted: (value) {
                      final query = value.trim();
                      if (query.isNotEmpty) _openWord(query);
                    },
                    onClear: () {
                      _controller.clear();
                      _onChanged('');
                    },
                    showClear: showSearch && _controller.text.isNotEmpty,
                  ),
                ),
                // 联想结果（聚焦后淡入，位于输入框下方）
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !showSearch,
                    child: AnimatedOpacity(
                      opacity: showSearch ? 1 : 0,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOut,
                      child: Column(
                        children: [
                          const SizedBox(height: 84),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _dismissSearch,
                              child: _SuggestionList(
                                suggestions: _suggestions,
                                hasQuery: _hasQuery,
                                onTap: _openWord,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(
            Icons.menu_book_rounded,
            size: 40,
            color: scheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '词典',
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.showClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool showClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(24),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: '输入英文或中文…',
          hintStyle: TextStyle(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          filled: false,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: showClear
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClear,
                )
              : null,
        ),
      ),
    );
  }
}

class _WordOfDayCard extends ConsumerWidget {
  const _WordOfDayCard({required this.onOpenWord});

  final void Function(String) onOpenWord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wordOfDay = ref.watch(wordOfDayProvider);

    return wordOfDay.when(
      loading: () => const SizedBox(
        height: 120,
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
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.wb_sunny_outlined,
                      size: 22,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '今日一词',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.tertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                entry.word,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (entry.phonetic != null)
                              Text(
                                entry.phonetic!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.translation ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.outline,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SuggestionList extends ConsumerWidget {
  const _SuggestionList({
    required this.suggestions,
    required this.hasQuery,
    required this.onTap,
  });

  final List<WordEntry> suggestions;
  final bool hasQuery;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (suggestions.isEmpty && !hasQuery) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tips_and_updates_outlined,
                size: 40, color: scheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              '输入英文或中文开始搜索',
              style: TextStyle(color: scheme.outline),
            ),
          ],
        ),
      );
    }
    if (suggestions.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的词',
          style: TextStyle(color: scheme.outline),
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
            color: scheme.primary,
          ),
          title: Text(
            entry.word,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: entry.translation != null &&
                  entry.translation!.isNotEmpty
              ? Text(
                  _firstSense(entry.translation!),
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

/// Returns the first parsed sense (e.g. "男人, 人类, 人") for list previews.
String _firstSense(String raw) {
  final items = parseTranslation(raw);
  return items.isEmpty ? raw.replaceAll(r'\n', '\n') : items.first.$2;
}
