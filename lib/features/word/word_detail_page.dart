import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/dict_repository.dart';
import '../../core/db/user_data.dart';
import '../../core/models/word_entry.dart';
import '../../core/network/online_dict.dart';
import '../../core/text/importance.dart';
import '../../core/text/translation_parse.dart';
import '../../core/tts/tts_service.dart';
import '../settings/settings_page.dart' show DefMode, defModeProvider;

class WordDetailPage extends ConsumerStatefulWidget {
  const WordDetailPage({super.key, required this.word});

  final String word;

  @override
  ConsumerState<WordDetailPage> createState() => _WordDetailPageState();
}

class _WordDetailPageState extends ConsumerState<WordDetailPage> {
  late String _word;
  late Future<_LookupResult> _entryFuture;
  bool _fav = false;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearching = false;
  List<WordEntry> _searchSuggestions = const [];
  bool _searchingLoading = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _word = widget.word;
    _entryFuture = _load(_word);
    _searchController.addListener(_onSearchInputChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchInputChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchInputChanged() {
    setState(() {});
  }

  Future<_LookupResult> _load(String word) async {
    final repo = await ref.read(dictRepositoryProvider.future);
    final user = await ref.read(userDataProvider.future);
    await user.addHistory(word);
    final isFav = user.isFavorite(word);
    if (mounted) setState(() => _fav = isFav);

    final entry = await repo.lookup(word);
    if (entry != null) return _LookupResult(entry: entry);

    final isCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(word);
    if (isCjk) {
      final related = await repo.suggestions(word, limit: 20);
      if (related.isNotEmpty) return _LookupResult(related: related);
    }
    return const _LookupResult();
  }

  void _openSearch() {
    setState(() {
      _isSearching = true;
      _searchSuggestions = const [];
      _searchingLoading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _isSearching = false;
      _searchSuggestions = const [];
      _searchingLoading = false;
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _searchSuggestions = const [];
        _searchingLoading = false;
      });
      return;
    }
    setState(() => _searchingLoading = true);
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      final repo = await ref.read(dictRepositoryProvider.future);
      final results = await repo.suggestions(query);
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _searchingLoading = false;
        _searchSuggestions = results;
      });
    });
  }

  void _selectWord(String word) {
    final target = word.trim();
    _closeSearch();
    if (target.isEmpty || target == _word) return;
    setState(() {
      _word = target;
      _entryFuture = _load(target);
    });
  }

  Future<void> _toggleFavorite(WordEntry entry) async {
    final user = await ref.read(userDataProvider.future);
    final added = await user.toggleFavorite(entry.word);
    if (!mounted) return;
    setState(() => _fav = added);
    ref.invalidate(favoritesProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(added ? '已加入生词本' : '已移出生词本'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    return PopScope(
      canPop: !_isSearching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSearching) {
          _closeSearch();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              // 1. 常规顶部栏与单词详情视图
              Column(
                children: [
                  IgnorePointer(
                    ignoring: _isSearching,
                    child: AnimatedOpacity(
                      opacity: _isSearching ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: SizedBox(
                        height: 56,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              if (canPop)
                                IconButton(
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  tooltip: _isSearching ? null : '返回上一页',
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                )
                              else
                                const SizedBox(width: 16),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _word,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: '重新查词',
                                icon: const Icon(Icons.search_rounded),
                                onPressed: _openSearch,
                              ),
                              IconButton(
                                tooltip: '生词本',
                                icon: Icon(
                                  _fav
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                ),
                                onPressed: () async {
                                  final result = await _entryFuture;
                                  if (result.entry != null) {
                                    _toggleFavorite(result.entry!);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.02),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(_word),
                        child: FutureBuilder<_LookupResult>(
                          future: _entryFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final result =
                                snapshot.data ?? const _LookupResult();
                            if (result.entry != null) {
                              return _EntryView(entry: result.entry!);
                            }
                            if (result.related.isNotEmpty) {
                              return _RelatedList(
                                query: _word,
                                related: result.related,
                              );
                            }
                            return _NotFound(word: _word);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // 2. 原位联想词浮层，与主页同款平滑淡入淡出（240ms easeOut）
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_isSearching,
                  child: AnimatedOpacity(
                    opacity: _isSearching ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    child: Material(
                      color: theme.scaffoldBackgroundColor,
                      child: Column(
                        children: [
                          const SizedBox(height: 76),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () {
                                if (_searchController.text.trim().isEmpty) {
                                  _closeSearch();
                                }
                              },
                              child: _DetailSuggestionList(
                                suggestions: _searchSuggestions,
                                hasQuery:
                                    _searchController.text.trim().isNotEmpty,
                                isLoading: _searchingLoading,
                                onTap: _selectWord,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. 悬浮搜索输入框：与主页完全一致的 340ms easeOutCubic 从屏幕上方平滑滑入
              AnimatedPositioned(
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutCubic,
                top: _isSearching ? 10 : -72,
                left: 20,
                right: 20,
                child: IgnorePointer(
                  ignoring: !_isSearching,
                  child: _DetailSearchField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _onSearchChanged,
                    onSubmitted: (val) {
                      final q = val.trim();
                      if (q.isNotEmpty) _selectWord(q);
                    },
                    onClear: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                    onBack: _closeSearch,
                    showClear:
                        _isSearching && _searchController.text.isNotEmpty,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailSearchField extends StatelessWidget {
  const _DetailSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onBack,
    required this.showClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onBack;
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
          prefixIcon: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          suffixIcon: showClear
              ? IconButton(
                  tooltip: '清除',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClear,
                )
              : null,
        ),
      ),
    );
  }
}

class _DetailSuggestionList extends StatelessWidget {
  const _DetailSuggestionList({
    required this.suggestions,
    required this.hasQuery,
    required this.isLoading,
    required this.onTap,
  });

  final List<WordEntry> suggestions;
  final bool hasQuery;
  final bool isLoading;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (suggestions.isEmpty && !hasQuery) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tips_and_updates_outlined,
              size: 40,
              color: scheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '输入英文或中文开始搜索',
              style: TextStyle(color: scheme.outline),
            ),
          ],
        ),
      );
    }
    if (isLoading && suggestions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (suggestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '没有匹配的词',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.outline),
          ),
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


class _LookupResult {
  const _LookupResult({this.entry, this.related = const []});

  final WordEntry? entry;
  final List<WordEntry> related;
}

class _RelatedList extends ConsumerWidget {
  const _RelatedList({required this.query, required this.related});

  final String query;
  final List<WordEntry> related;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Row(
          children: [
            Icon(Icons.translate_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '与"$query"相关的词条',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '未找到 "$query"，为你展示词库中含该释义的词',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: 12),
        for (final entry in related)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.menu_book_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              title: Text(
                entry.word,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: entry.translation != null &&
                      entry.translation!.isNotEmpty
                  ? Text(
                      _firstSense(entry.translation!),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context)
                    .push(MaterialPageRoute(
                      builder: (_) => WordDetailPage(word: entry.word),
                    ))
                    .then((_) => ref.invalidate(favoritesProvider));
              },
            ),
          ),
      ],
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: scheme.outline),
            const SizedBox(height: 16),
            Text('未找到 "$word"', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '词库中暂无此词，试试其他拼写',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryView extends ConsumerWidget {
  const _EntryView({required this.entry});

  final WordEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                entry.word,
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _SpeakButton(accent: Accent.us, text: entry.word),
            const SizedBox(width: 8),
            _SpeakButton(accent: Accent.uk, text: entry.word),
          ],
        ),
        if (entry.phonetic != null && entry.phonetic!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                entry.phonetic!,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _ImportanceBadges(entry: entry),
        const SizedBox(height: 20),
        if (entry.translation != null && entry.translation!.isNotEmpty)
          ..._buildPosGroups(entry.translation!),
        if (entry.definition != null && entry.definition!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _DefinitionSection(entry: entry),
        ],
        if (entry.exchange != null && entry.exchange!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: '词形变化',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: parseExchange(entry.exchange!)
                    .map(
                      (e) => Chip(
                        label: Text(
                          '${e.$1} · ${e.$2}'.replaceAll("'", '’'),
                          style: theme.textTheme.bodySmall,
                        ),
                        side: BorderSide.none,
                        backgroundColor: scheme.surfaceContainerHighest,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _OnlineZhSection(word: entry.word),
        const SizedBox(height: 16),
        _OnlineSection(word: entry.word),
      ],
    );
  }
}

/// Shows the word's importance: a "common word" badge (ECDICT tag) plus a
/// frequency-level badge derived from the contemporary corpus rank.
class _ImportanceBadges extends StatelessWidget {
  const _ImportanceBadges({required this.entry});

  final WordEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final importance = importanceFromFrq(entry.frq);

    final chips = <Widget>[];
    if (entry.tag == '1') {
      chips.add(_Badge(
        icon: Icons.star_rounded,
        text: '常用词',
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
      ));
    }
    if (importance != WordImportance.unknown) {
      chips.add(_Badge(
        icon: Icons.trending_up_rounded,
        text: importance.label,
        tooltip: importance.description,
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
    this.tooltip,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: foreground),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: label,
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

/// Renders the WordNet definition as bilingual / Chinese-only /
/// English-only depending on the user's display preference.
class _DefinitionSection extends ConsumerWidget {
  const _DefinitionSection({required this.entry});

  final WordEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = ref.watch(defModeProvider);

    final enLines = splitEscapedLines(entry.definition!);
    final cnLines = entry.definitionCn == null
        ? <String>[]
        : splitEscapedLines(entry.definitionCn!);

    if (mode == DefMode.en || cnLines.isEmpty) {
      return _SectionCard(
        title: '英英释义',
        children: [
          for (final line in enLines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                line,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
            ),
        ],
      );
    }

    if (mode == DefMode.cn) {
      return _SectionCard(
        title: '中文释义',
        children: [
          for (final line in cnLines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                line,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
            ),
        ],
      );
    }

    // bilingual: pair up English and Chinese lines
    final rows = <Widget>[];
    for (var i = 0; i < enLines.length; i++) {
      final cn = i < cnLines.length ? cnLines[i] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                enLines[i],
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              if (cn != null) ...[
                const SizedBox(height: 2),
                Text(
                  cn,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return _SectionCard(
      title: '英英释义',
      children: rows,
    );
  }
}

/// Chinese senses supplement fetched from Youdao, shown above the English
/// online section. Hidden when offline or when the API returns nothing.
class _OnlineZhSection extends ConsumerWidget {
  const _OnlineZhSection({required this.word});

  final String word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineZhLookupProvider(word));
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return online.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        if (data == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.translate_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  '在线中文释义',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (data.phonetics.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final entry in data.phonetics.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${entry.key == 'uk' ? '英' : '美'} /${entry.value}/',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            for (final sense in data.senses) ...[
              if (data.senses.indexOf(sense) > 0)
                const SizedBox(height: 12),
              _PosGroup(pos: sense.pos, senses: sense.definitions),
            ],
          ],
        );
      },
    );
  }
}

class _OnlineSection extends ConsumerWidget {
  const _OnlineSection({required this.word});

  final String word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineLookupProvider(word));
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return online.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        if (data == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.language_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  '在线补充',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (data.senses.isNotEmpty)
              for (final sense in data.senses) ...[
                if (data.senses.indexOf(sense) > 0)
                  const SizedBox(height: 12),
                _PosGroup(pos: sense.pos, senses: sense.definitions),
              ],
            if (data.examples.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionCard(
                title: '例句',
                children: [
                  for (final example in data.examples)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6, right: 10),
                            child: Icon(
                              Icons.format_quote_rounded,
                              size: 16,
                              color: scheme.outlineVariant,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              example,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(height: 1.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {  const _SectionCard({this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Groups parsed (pos, text) translations into per-pos cards.
List<Widget> _buildPosGroups(String raw) {
  final items = parseTranslation(raw);
  if (items.isEmpty) return const [];

  final groups = <(String, List<String>)>[];
  for (final item in items) {
    if (groups.isNotEmpty && groups.last.$1 == item.$1) {
      groups.last.$2.add(item.$2);
    } else {
      groups.add((item.$1, [item.$2]));
    }
  }

  return [
    for (final group in groups) ...[
      if (groups.indexOf(group) > 0) const SizedBox(height: 12),
      _PosGroup(pos: group.$1, senses: group.$2),
    ],
  ];
}

class _PosGroup extends StatelessWidget {
  const _PosGroup({required this.pos, required this.senses});

  final String pos;
  final List<String> senses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isRealPos = pos.isNotEmpty && pos != '[网络]';

    final badgeColor = isRealPos
        ? _posColor(pos, scheme)
        : scheme.surfaceContainerHighest;
    final badgeFg = isRealPos
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isRealPos) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      pos,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: badgeFg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 1.2,
                      color: badgeColor.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            for (var i = 0; i < senses.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(top: 2, right: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: badgeFg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        senses[i],
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Color _posColor(String pos, ColorScheme scheme) {
    final p = pos.toLowerCase();
    if (p.startsWith('n')) return scheme.tertiaryContainer;
    if (p.startsWith('v')) return scheme.primaryContainer;
    if (p.startsWith('adj') || p.startsWith('a.')) {
      return scheme.secondaryContainer;
    }
    if (p.startsWith('adv') || p.startsWith('ad.')) {
      return scheme.surfaceContainerHighest;
    }
    if (p.startsWith('prep')) return scheme.errorContainer;
    if (p.startsWith('conj')) return scheme.primaryContainer;
    if (p.startsWith('pron')) return scheme.secondaryContainer;
    if (p.startsWith('interj') || p.startsWith('int.')) {
      return scheme.tertiaryContainer;
    }
    return scheme.surfaceContainerHighest;
  }
}

class _SpeakButton extends ConsumerWidget {
  const _SpeakButton({required this.accent, required this.text});

  final Accent accent;
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final label = accent == Accent.us ? '美' : '英';
    return Tooltip(
      message: '$label音发音',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => TtsService.instance.speak(text, accent: accent),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.volume_up_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 2),
              Text(
                label,
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Returns the first parsed sense (e.g. "男人, 人类, 人") for list previews.
String _firstSense(String raw) {
  final items = parseTranslation(raw);
  return items.isEmpty ? raw.replaceAll(r'\n', '\n') : items.first.$2;
}

