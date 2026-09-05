import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text/lookup_text.dart';
import '../features/settings/settings_page.dart';
import 'router.dart';
import 'theme.dart';

class DictApp extends ConsumerStatefulWidget {
  const DictApp({super.key});

  @override
  ConsumerState<DictApp> createState() => _DictAppState();
}

class _DictAppState extends ConsumerState<DictApp> {
  static const _channel = MethodChannel('com.example.dict/process_text');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(themeModeProvider.notifier).init();
      ref.read(themeColorProvider.notifier).init();
      ref.read(defModeProvider.notifier).init();
      ref.read(ttsModeProvider.notifier).init();
      ref.read(audioDuckingProvider.notifier).init();
      ref.read(quickLookupProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'lookupText') return null;
    final raw = call.arguments as String?;
    if (raw == null || raw.isEmpty) return null;
    final word = extractLookupWord(raw);
    if (word == null || !mounted) return null;
    final router = ref.read(routerProvider);
    router.push('/word/${Uri.encodeComponent(word)}');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final themeColor = ref.watch(themeColorProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightSeed = themeColor == AppThemeColor.system
            ? lightDynamic?.primary
            : themeColor.seed;
        final darkSeed = themeColor == AppThemeColor.system
            ? darkDynamic?.primary
            : themeColor.seed;
        return MaterialApp.router(
          title: '词典',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(lightSeed),
          darkTheme: AppTheme.dark(darkSeed),
          themeMode: switch (themeMode) {
            ThemeModePref.system => ThemeMode.system,
            ThemeModePref.light => ThemeMode.light,
            ThemeModePref.dark => ThemeMode.dark,
          },
          routerConfig: router,
        );
      },
    );
  }
}
