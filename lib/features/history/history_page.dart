import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/user_data.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final history = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '浏览历史',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (history.valueOrNull?.isNotEmpty ?? false)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final user = await ref.read(userDataProvider.future);
                await user.clearHistory();
                ref.invalidate(historyProvider);
              },
            ),
        ],
      ),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const SizedBox.shrink(),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded,
                      size: 64, color: scheme.outlineVariant),
                  const SizedBox(height: 12),
                  Text(
                    '暂无浏览记录',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final word = list[index];
              return Card(
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: scheme.secondaryContainer,
                    child: Icon(
                      Icons.history_rounded,
                      color: scheme.onSecondaryContainer,
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
              );
            },
          );
        },
      ),
    );
  }
}
