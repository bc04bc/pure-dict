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

  @override
  void initState() {
    super.initState();
    _word = widget.word;
    _entryFuture = _load(_word);
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

  /// Opens the in-page re-lookup search. Picking a word (or submitting the
  /// query) switches the current page to it in place, without leaving the
  /// detail view or stacking routes.
  Future<void> _startSearch() async {
    final result = await showSearch<String>(
      context: context,
      delegate: _WordSearchDelegate(),
    );
    if (!mounted || result == null || result.isEmpty || result == _word) {
      return;
    }
    setState(() {
      _word = result;
      _entryFuture = _load(result);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_word, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '重新查词',
            icon: const Icon(Icons.search_rounded),
            onPressed: _startSearch,
          ),
          IconButton(
            tooltip: '生词本',
            icon: Icon(_fav ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () async {
              final result = await _entryFuture;
              if (result.entry != null) _toggleFavorite(result.entry!);
            },
          ),
        ],
      ),
      body: FutureBuilder<_LookupResult>(
        future: _entryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snapshot.data ?? const _LookupResult();
          if (result.entry != null) {
            return _EntryView(entry: result.entry!);
          }
          if (result.related.isNotEmpty) {
            return _RelatedList(query: _word, related: result.related);
          }
          return _NotFound(word: _word);
        },
      ),
    );
  }
}

class _LookupResult {
  const _LookupResult({this.entry, this.related = const []});

  final WordEntry? entry;
  final List<WordEntry> related;
}

/// Full-screen re-lookup search with live dictionary suggestions. Selecting a
/// suggestion (or submitting the query) returns the chosen word to the detail
/// page, which switches to it in place.
class _WordSearchDelegate extends SearchDelegate<String> {
  @override
  String get searchFieldLabel => '输入英文或中文…';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: '清除',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      tooltip: '返回',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _SearchSuggestions(
      query: query,
      onSelect: (word) => close(context, word),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _SearchSuggestions(
      query: query,
      onSelect: (word) => close(context, word),
    );
  }
}

/// Live suggestion list backing the re-lookup search. Debounced so typing
/// feels responsive without hammering SQLite on every keystroke.
class _SearchSuggestions extends ConsumerStatefulWidget {
  const _SearchSuggestions({required this.query, required this.onSelect});

  final String query;
  final ValueChanged<String> onSelect;

  @override
  ConsumerState<_SearchSuggestions> createState() => _SearchSuggestionsState();
}

class _SearchSuggestionsState extends ConsumerState<_SearchSuggestions> {
  Timer? _debounce;
  List<WordEntry> _suggestions = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(_SearchSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    _debounce?.cancel();
    final query = widget.query.trim();
    if (query.isEmpty) {
      if (_searching || _suggestions.isNotEmpty) {
        setState(() {
          _searching = false;
          _suggestions = const [];
        });
      }
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final repo = await ref.read(dictRepositoryProvider.future);
      final results = await repo.suggestions(query);
      if (!mounted || widget.query.trim() != query) return;
      setState(() {
        _searching = false;
        _suggestions = results;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = widget.query.trim();

    if (query.isEmpty) {
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
            Text('输入英文或中文开始搜索', style: TextStyle(color: scheme.outline)),
          ],
        ),
      );
    }
    if (_searching && _suggestions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_suggestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '没有匹配的词，按键盘搜索键直接查询',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.outline),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: _suggestions.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) {
        final entry = _suggestions[index];
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
          subtitle: entry.translation != null && entry.translation!.isNotEmpty
              ? Text(
                  _firstSense(entry.translation!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => widget.onSelect(entry.word),
        );
      },
    );
  }
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

