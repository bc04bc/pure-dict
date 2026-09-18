import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/dict_repository.dart';
import '../../core/db/user_data.dart';
import '../../core/models/study_entry.dart';
import '../../core/models/word_entry.dart';
import '../../core/study/urgency_algorithm.dart';
import '../../core/text/importance.dart';
import '../../core/text/translation_parse.dart';
import 'study_view.dart';

enum WordbookViewMode { review, list }

final studyDeckProvider = FutureProvider<List<StudyCardItem>>((ref) async {
  final user = await ref.watch(userDataProvider.future);
  final repo = await ref.watch(dictRepositoryProvider.future);
  final entries = await user.getActiveStudyEntries();
  if (entries.isEmpty) return const [];

  final now = DateTime.now();
  final items = <StudyCardItem>[];
  for (final e in entries) {
    final dictEntry = await repo.lookup(e.word);
    final importance = importanceFromFrq(dictEntry?.frq);
    final score = UrgencyCalculator.calculateScore(
      entry: e,
      importance: importance,
      now: now,
    );
    items.add(StudyCardItem(
      userWord: e,
      dictEntry: dictEntry,
      urgencyScore: score,
    ));
  }

  // Sort by highest urgency score first
  items.sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));

  final quota = user.dailyReviewQuota;
  if (quota > 0 && items.length > quota) {
    return items.sublist(0, quota);
  }
  return items;
});

class WordbookListItem {
  const WordbookListItem({
    required this.studyEntry,
    this.dictEntry,
    required this.urgencyScore,
  });

  final UserWordEntry studyEntry;
  final WordEntry? dictEntry;
  final double urgencyScore;
}

final allStudyWordsProvider =
    FutureProvider<List<WordbookListItem>>((ref) async {
  final user = await ref.watch(userDataProvider.future);
  final repo = await ref.watch(dictRepositoryProvider.future);
  final entries = await user.getActiveStudyEntries();
  if (entries.isEmpty) return const [];

  final now = DateTime.now();
  final items = <WordbookListItem>[];
  for (final e in entries) {
    final dictEntry = await repo.lookup(e.word);
    final importance = importanceFromFrq(dictEntry?.frq);
    final score = UrgencyCalculator.calculateScore(
      entry: e,
      importance: importance,
      now: now,
    );
    items.add(WordbookListItem(
      studyEntry: e,
      dictEntry: dictEntry,
      urgencyScore: score,
    ));
  }

  items.sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));
  return items;
});

class WordbookPage extends ConsumerStatefulWidget {
  const WordbookPage({super.key});

  @override
  ConsumerState<WordbookPage> createState() => _WordbookPageState();
}

class _WordbookPageState extends ConsumerState<WordbookPage> {
  WordbookViewMode _viewMode = WordbookViewMode.review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final userAsync = ref.watch(userDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '背单词',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(studyDeckProvider);
              ref.invalidate(allStudyWordsProvider);
              ref.invalidate(favoritesProvider);
            },
          ),
        ],
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const SizedBox.shrink(),
        data: (user) {
          if (!user.studyEnabled) {
            return _StudyDisabledState(
              scheme: scheme,
              theme: theme,
              onEnable: () async {
                await user.setStudyEnabled(true);
                ref.invalidate(userDataProvider);
              },
            );
          }

          final deckAsync = ref.watch(studyDeckProvider);
          final allWordsAsync = ref.watch(allStudyWordsProvider);

          return Column(
            children: [
              // Segmented Tab switcher
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<WordbookViewMode>(
                    segments: [
                      ButtonSegment(
                        value: WordbookViewMode.review,
                        label: Text(
                          deckAsync.valueOrNull != null
                              ? '今日复习 (${deckAsync.valueOrNull!.length})'
                              : '今日复习',
                        ),
                        icon: const Icon(Icons.psychology_outlined),
                      ),
                      ButtonSegment(
                        value: WordbookViewMode.list,
                        label: Text(
                          allWordsAsync.valueOrNull != null
                              ? '生词库 (${allWordsAsync.valueOrNull!.length})'
                              : '生词库',
                        ),
                        icon: const Icon(Icons.list_alt_rounded),
                      ),
                    ],
                    selected: {_viewMode},
                    onSelectionChanged: (set) =>
                        setState(() => _viewMode = set.first),
                  ),
                ),
              ),

              // Tab content
              Expanded(
                child: switch (_viewMode) {
                  WordbookViewMode.review => deckAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Center(child: Text('加载失败: $err')),
                      data: (items) => StudySessionView(
                        items: items,
                        onSessionFinished: () {
                          ref.invalidate(studyDeckProvider);
                          ref.invalidate(allStudyWordsProvider);
                          setState(() => _viewMode = WordbookViewMode.list);
                        },
                      ),
                    ),
                  WordbookViewMode.list => allWordsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Center(child: Text('加载失败: $err')),
                      data: (list) {
                        if (list.isEmpty) {
                          return _EmptyStudyState(scheme: scheme, theme: theme);
                        }
                        return _AllWordsListView(
                          items: list,
                          onOpenWord: (w) => context.push('/word/$w'),
                          onRemove: (w) async {
                            await user.removeFromStudy(w);
                            ref.invalidate(studyDeckProvider);
                            ref.invalidate(allStudyWordsProvider);
                            ref.invalidate(favoritesProvider);
                          },
                        );
                      },
                    ),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AllWordsListView extends StatelessWidget {
  const _AllWordsListView({
    required this.items,
    required this.onOpenWord,
    required this.onRemove,
  });

  final List<WordbookListItem> items;
  final void Function(String) onOpenWord;
  final void Function(String) onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final word = item.studyEntry.word;
        final dict = item.dictEntry;
        final queryCount = item.studyEntry.queryCount;
        final stage = item.studyEntry.srsStage;

        return Dismissible(
          key: ValueKey(word),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('移出',
                    style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Icon(Icons.delete_outline, color: scheme.onErrorContainer),
              ],
            ),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('移出生词库'),
                content: Text('确定要将 "$word" 移出生词库吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    ),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('移出'),
                  ),
                ],
              ),
            ) ?? false;
          },
          onDismissed: (_) => onRemove(word),
          child: Card(
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  '$queryCount',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              title: Row(
                children: [
                  Text(
                    word,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  if (stage > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '阶段 $stage',
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
              subtitle: dict?.translation != null &&
                      dict!.translation!.isNotEmpty
                  ? Text(
                      _firstSense(dict.translation!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text('查过 $queryCount 次',
                      style: TextStyle(color: scheme.outline)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onOpenWord(word),
            ),
          ),
        );
      },
    );
  }

  String _firstSense(String raw) {
    final parsed = parseTranslation(raw);
    return parsed.isEmpty ? raw.replaceAll(r'\n', '\n') : parsed.first.$2;
  }
}

class _EmptyStudyState extends StatelessWidget {
  const _EmptyStudyState({required this.scheme, required this.theme});

  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_stories_outlined,
              size: 64, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            '生词库还是空的',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '开启背单词后，每次查词都会自动纳入此处',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _StudyDisabledState extends StatelessWidget {
  const _StudyDisabledState({
    required this.scheme,
    required this.theme,
    required this.onEnable,
  });

  final ColorScheme scheme;
  final ThemeData theme;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pause_circle_outline_rounded,
                size: 64, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text('背单词功能已关闭', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '开启后，用户在应用内或长按划词查询的英文单词将自动入库，基于查词频次与遗忘曲线智能规划复习。',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onEnable,
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('开启背单词'),
            ),
          ],
        ),
      ),
    );
  }
}
