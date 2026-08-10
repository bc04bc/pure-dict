import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../core/db/app_database.dart';
import '../../core/db/user_data.dart';
import '../../core/tts/tts_service.dart';

const quickLookupChannel = MethodChannel('com.example.dict/quick_lookup');

enum ThemeModePref { system, light, dark }

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeModePref>(
  (_) => ThemeModeNotifier(),
);

final themeColorProvider =
    StateNotifierProvider<ThemeColorNotifier, AppThemeColor>(
  (_) => ThemeColorNotifier(),
);

final ttsModeProvider =
    StateNotifierProvider<TtsModeNotifier, TtsMode>((_) => TtsModeNotifier());

class TtsModeNotifier extends StateNotifier<TtsMode> {
  TtsModeNotifier() : super(TtsService.instance.mode);

  Future<void> init() async {
    await TtsService.instance.ready;
    state = TtsService.instance.mode;
  }

  Future<void> set(TtsMode mode) async {
    await TtsService.instance.setMode(mode);
    state = mode;
  }
}

class ThemeColorNotifier extends StateNotifier<AppThemeColor> {
  static const _key = 'theme_color';

  ThemeColorNotifier() : super(AppThemeColor.system);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    state = AppThemeColor.values.firstWhere(
      (c) => c.name == saved,
      orElse: () => AppThemeColor.system,
    );
  }

  Future<void> set(AppThemeColor value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
    state = value;
  }
}

final quickLookupProvider =
    StateNotifierProvider<QuickLookupNotifier, bool>((_) => QuickLookupNotifier());

class QuickLookupNotifier extends StateNotifier<bool> {
  QuickLookupNotifier() : super(false);

  Future<void> init() async {
    try {
      final enabled = await quickLookupChannel.invokeMethod<bool>('isEnabled') ?? false;
      state = enabled;
    } catch (_) {}
  }

  Future<void> set(bool enabled) async {
    try {
      if (enabled) {
        final granted =
            await quickLookupChannel.invokeMethod<bool>('enable') ?? false;
        state = granted;
      } else {
        await quickLookupChannel.invokeMethod<bool>('disable');
        state = false;
      }
    } catch (_) {}
  }
}

class ThemeModeNotifier extends StateNotifier<ThemeModePref> {
  static const _key = 'theme_mode';

  ThemeModeNotifier() : super(ThemeModePref.system);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    state = switch (prefs.getString(_key)) {
      'dark' => ThemeModePref.dark,
      'light' => ThemeModePref.light,
      _ => ThemeModePref.system,
    };
  }

  Future<void> set(ThemeModePref value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      value == ThemeModePref.dark
          ? 'dark'
          : value == ThemeModePref.light
              ? 'light'
              : 'system',
    );
    state = value;
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '设置',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SectionLabel('外观'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.brightness_6_outlined),
                    title: const Text('主题模式'),
                    subtitle: Text(
                      switch (themeMode) {
                        ThemeModePref.system => '跟随系统',
                        ThemeModePref.light => '浅色',
                        ThemeModePref.dark => '深色',
                      },
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeModePref>(
                      style: ButtonStyle(
                        visualDensity: VisualDensity.standard,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: ThemeModePref.system,
                          label: Text('跟随系统'),
                        ),
                        ButtonSegment(
                          value: ThemeModePref.light,
                          label: Text('浅色'),
                        ),
                        ButtonSegment(
                          value: ThemeModePref.dark,
                          label: Text('深色'),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (selection) =>
                          ref.read(themeModeProvider.notifier).set(selection.first),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('主题颜色'),
                    subtitle: Text(
                      ref.watch(themeColorProvider).description,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final color in AppThemeColor.values)
                        _ColorOption(
                          color: color,
                          selected: ref.watch(themeColorProvider) == color,
                          onTap: () =>
                              ref.read(themeColorProvider.notifier).set(color),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('发音'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('发音来源'),
                  subtitle: Text(_modeDescription(ref.watch(ttsModeProvider))),
                ),
                const Divider(height: 1),
                RadioGroup<TtsMode>(
                  groupValue: ref.watch(ttsModeProvider),
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(ttsModeProvider.notifier).set(value);
                    }
                  },
                  child: Column(
                    children: [
                      for (final mode in TtsMode.values)
                        RadioListTile<TtsMode>(
                          title: Text(mode.label),
                          subtitle: Text(
                            _modeDescription(mode),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          value: mode,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('快捷查词'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('通知栏查词'),
                  subtitle: const Text('在通知栏直接输入单词，快速弹出查词结果'),
                  value: ref.watch(quickLookupProvider),
                  onChanged: (value) =>
                      ref.read(quickLookupProvider.notifier).set(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('音频缓存'),
          _AudioCacheCard(),
          const SizedBox(height: 24),
          _SectionLabel('数据'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('清除浏览历史'),
                  subtitle: const Text('删除所有查询记录'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final user = await ref.read(userDataProvider.future);
                    await user.clearHistory();
                    ref.invalidate(historyProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('已清除'),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outlined),
                  title: const Text('清空生词本'),
                  subtitle: const Text('删除所有收藏的词'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final user = await ref.read(userDataProvider.future);
                    await user.clearFavorites();
                    ref.invalidate(favoritesProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('已清空'),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('重建离线词库'),
                  subtitle: const Text('重新从安装包解压词库文件'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await AppDatabase.reset();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('词库已重置，重启应用后生效'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('其他'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('关于'),
              subtitle: const Text('版本信息与开源许可'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/about'),
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              '词典 v1.0.1\n数据来源：ECDICT 开源词库',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

String _modeDescription(TtsMode mode) => switch (mode) {
      TtsMode.edge => '微软神经网络语音，音质最佳，需网络',
      TtsMode.local => '设备自带语音引擎，完全离线',
      TtsMode.youdao => '有道词典真人发音，需网络，仅英文',
      TtsMode.baidu => '百度翻译发音，需网络，仅英文',
    };

class _ColorOption extends StatelessWidget {
  const _ColorOption({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final AppThemeColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = color.seed ??
        scheme.primary; // dynamic: show primary as a stand-in
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: scheme.onSurface, width: 3)
                    : Border.all(color: scheme.outlineVariant, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: fill.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              color.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioCacheCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AudioCacheCard> createState() => _AudioCacheCardState();
}

class _AudioCacheCardState extends ConsumerState<_AudioCacheCard> {
  bool _cacheEnabled = true;
  bool _loading = true;
  int? _sizeBytes;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final tts = TtsService.instance;
    await tts.ready;
    final size = await tts.cacheSize();
    if (!mounted) return;
    setState(() {
      _cacheEnabled = tts.cacheEnabled;
      _sizeBytes = size;
      _loading = false;
    });
  }

  String get _sizeLabel {
    final bytes = _sizeBytes ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.sd_storage_outlined),
            title: const Text('音频缓存'),
            subtitle: Text(
              _cacheEnabled ? '发音音频缓存到本地，节省流量' : '每次在线获取，不保存音频',
            ),
            value: _cacheEnabled,
            onChanged: (value) async {
              setState(() => _cacheEnabled = value);
              await TtsService.instance.setCacheEnabled(value);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清除音频缓存'),
            subtitle: Text(
              _loading ? '正在统计…' : '当前占用 $_sizeLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            enabled: !_loading && (_sizeBytes ?? 0) > 0,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await TtsService.instance.clearCache();
              final size = await TtsService.instance.cacheSize();
              if (!mounted || !context.mounted) return;
              setState(() => _sizeBytes = size);
              final messenger = ScaffoldMessenger.of(context);
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('音频缓存已清除'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            },
          ),
        ],
      ),
    );
  }
}
