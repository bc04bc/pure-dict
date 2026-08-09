import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/user_data.dart';

class WordbookPage extends ConsumerWidget {
  const WordbookPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '生词本',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (favorites.valueOrNull?.isNotEmpty ?? false)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final user = await ref.read(userDataProvider.future);
                await user.clearFavorites();
                ref.invalidate(favoritesProvider);
              },
            ),
        ],
      ),
      body: favorites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const SizedBox.shrink(),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyState(scheme: scheme, theme: theme);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final word = list[index];
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
                  child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
                ),
                onDismissed: (_) async {
                  final user = await ref.read(userDataProvider.future);
                  await user.toggleFavorite(word);
                  ref.invalidate(favoritesProvider);
                },
                child: Card(
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(
                        Icons.bookmark_rounded,
                        color: scheme.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      word,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/word/$word'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scheme, required this.theme});

  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border_rounded, size: 64, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            '生词本还是空的',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '查词时点击右上角书签即可收藏',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
