import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/user_data.dart';
import '../../core/models/study_entry.dart';
import '../../core/models/word_entry.dart';
import '../../core/study/urgency_algorithm.dart';
import '../../core/text/importance.dart';
import '../../core/text/translation_parse.dart';
import '../../core/tts/tts_service.dart';

class StudyCardItem {
  const StudyCardItem({
    required this.userWord,
    this.dictEntry,
    required this.urgencyScore,
  });

  final UserWordEntry userWord;
  final WordEntry? dictEntry;
  final double urgencyScore;
}

class StudySessionView extends ConsumerStatefulWidget {
  const StudySessionView({
    super.key,
    required this.items,
    required this.onSessionFinished,
  });

  final List<StudyCardItem> items;
  final VoidCallback onSessionFinished;

  @override
  ConsumerState<StudySessionView> createState() => _StudySessionViewState();
}

class _StudySessionViewState extends ConsumerState<StudySessionView> {
  int _currentIndex = 0;
  bool _revealed = false;
  int _reviewedCount = 0;

  void _nextWord(ReviewFeedback feedback) async {
    if (_currentIndex >= widget.items.length) return;

    final currentItem = widget.items[_currentIndex];
    final updated = UrgencyCalculator.processReview(
      entry: currentItem.userWord,
      feedback: feedback,
    );

    final userData = await ref.read(userDataProvider.future);
    await userData.saveUserWord(updated);

    setState(() {
      _reviewedCount++;
      _revealed = false;
      if (_currentIndex < widget.items.length - 1) {
        _currentIndex++;
      } else {
        _currentIndex++;
        widget.onSessionFinished();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (widget.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text('暂无待复习的单词', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '在日常查词或划词时，生词会自动汇集到这里',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_currentIndex >= widget.items.length) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.celebration_rounded,
                    size: 40, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 20),
              Text('今日复习完成！',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                '本次共复习了 $_reviewedCount 个单词，记忆又加深了一步。',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: widget.onSessionFinished,
                child: const Text('返回生词列表'),
              ),
            ],
          ),
        ),
      );
    }

    final item = widget.items[_currentIndex];
    final dict = item.dictEntry;
    final progress = (_currentIndex + 1) / widget.items.length;
    final importance = importanceFromFrq(dict?.frq);

    return Column(
      children: [
        // Top progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '今日待背 ${_currentIndex + 1} / ${widget.items.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '查过 ${item.userWord.queryCount} 次',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                borderRadius: BorderRadius.circular(8),
                minHeight: 6,
              ),
            ],
          ),
        ),

        // Main Flashcard
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  if (!_revealed) setState(() => _revealed = true);
                },
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header: badges
                      Row(
                        children: [
                          if (importance != WordImportance.unknown)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                importance.label,
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.volume_up_rounded),
                            tooltip: '朗读',
                            onPressed: () => TtsService.instance.speak(
                              item.userWord.word,
                              accent: Accent.us,
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // Word
                      Center(
                        child: Text(
                          item.userWord.word,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      // Phonetic
                      if (dict?.phonetic != null && dict!.phonetic!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Center(
                            child: Text(
                              dict.phonetic!,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ),

                      const Spacer(),

                      // Back side (Translations)
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 250),
                        crossFadeState: _revealed
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.touch_app_outlined,
                                    size: 16, color: scheme.outline),
                                const SizedBox(width: 8),
                                Text(
                                  '点击卡片翻看释义',
                                  style: TextStyle(
                                    color: scheme.outline,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        secondChild: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(),
                            const SizedBox(height: 8),
                            if (dict?.translation != null &&
                                dict!.translation!.isNotEmpty)
                              ..._buildSimpleTranslation(dict.translation!),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Bottom Feedback Controls (visible when revealed)
        AnimatedOpacity(
          opacity: _revealed ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_revealed,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                        side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => _nextWord(ReviewFeedback.again),
                      child: const Text('忘记了',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.tertiary,
                        side: BorderSide(color: scheme.tertiary.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => _nextWord(ReviewFeedback.hard),
                      child: const Text('模糊',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => _nextWord(ReviewFeedback.good),
                      child: const Text('记住了',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSimpleTranslation(String raw) {
    final parsed = parseTranslation(raw);
    if (parsed.isEmpty) {
      return [
        Text(raw.replaceAll(r'\n', '\n'),
            maxLines: 4, overflow: TextOverflow.ellipsis)
      ];
    }

    return parsed.take(3).map((item) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.$1.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 6, top: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.$1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            Expanded(
              child: Text(
                item.$2,
                style: const TextStyle(fontSize: 14, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
