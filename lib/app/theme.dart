import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppThemeColor {
  system('跟随系统', 'Android 12+ 自动取色', null),
  blue('经典蓝', '清新蓝调', Color(0xFF3D6BFF)),
  cream('奶油黄', '温暖柔和的奶油色', Color(0xFFB58B3A));

  const AppThemeColor(this.label, this.description, this.seed);

  final String label;
  final String description;
  final Color? seed;
}

class AppTheme {
  AppTheme._();

  /// Claude-style warm cream palette
  static const cream = _CreamPalette();

  static ThemeData light(Color? seed) => _build(Brightness.light, seed);
  static ThemeData dark(Color? seed) => _build(Brightness.dark, seed);

  static ThemeData _build(Brightness brightness, Color? seed) {
    final isCream = seed == AppThemeColor.cream.seed;
    final scheme = isCream
        ? _creamScheme(brightness)
        : ColorScheme.fromSeed(
            seedColor: seed ?? AppThemeColor.blue.seed!,
            brightness: brightness,
          );

    final isLight = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isCream && isLight
          ? cream.background
          : scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
          statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
          systemNavigationBarColor:
              isCream && isLight ? cream.background : scheme.surface,
          systemNavigationBarIconBrightness:
              isLight ? Brightness.dark : Brightness.light,
        ),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isCream && isLight ? cream.divider : scheme.outlineVariant,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        color: isCream && isLight ? cream.readingArea : scheme.surfaceContainerLow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isCream && isLight
            ? cream.secondaryBackground
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  static ColorScheme _creamScheme(Brightness brightness) =>
      brightness == Brightness.light ? _creamLight() : _creamDark();

  static ColorScheme _creamLight() => const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFFB58B3A),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFEBDCB5),
        onPrimaryContainer: Color(0xFF3A2F15),
        secondary: Color(0xFF9C7A33),
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: Color(0xFFEAD9B0),
        onSecondaryContainer: Color(0xFF33290F),
        tertiary: Color(0xFF8A7B5A),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFE6DCC4),
        onTertiaryContainer: Color(0xFF2C2516),
        error: Color(0xFFBA1A1A),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF410002),
        surface: Color(0xFFFAF5E8),
        onSurface: Color(0xFF302D27),
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: Color(0xFFF5EFDF),
        surfaceContainer: Color(0xFFF0E8D2),
        surfaceContainerHigh: Color(0xFFE9DFC6),
        surfaceContainerHighest: Color(0xFFE2D6BA),
        onSurfaceVariant: Color(0xFF706A5E),
        outline: Color(0xFFDED4BA),
        outlineVariant: Color(0xFFDED4BA),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFF4A463D),
        onInverseSurface: Color(0xFFF4EFE2),
        inversePrimary: Color(0xFFD8BC7F),
        surfaceTint: Color(0xFFB58B3A),
      );

  static ColorScheme _creamDark() => const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFFD8BC7F),
        onPrimary: Color(0xFF3A2F15),
        primaryContainer: Color(0xFF5C4A22),
        onPrimaryContainer: Color(0xFFF0E3C2),
        secondary: Color(0xFFD3BC85),
        onSecondary: Color(0xFF3A3016),
        secondaryContainer: Color(0xFF55431C),
        onSecondaryContainer: Color(0xFFF0E3C2),
        tertiary: Color(0xFFC9BC9E),
        onTertiary: Color(0xFF322D1F),
        tertiaryContainer: Color(0xFF4A4330),
        onTertiaryContainer: Color(0xFFE6DCC4),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: Color(0xFF1E1B13),
        onSurface: Color(0xFFEAE4D5),
        surfaceContainerLowest: Color(0xFF19160F),
        surfaceContainerLow: Color(0xFF262218),
        surfaceContainer: Color(0xFF2B261C),
        surfaceContainerHigh: Color(0xFF363025),
        surfaceContainerHighest: Color(0xFF413B2F),
        onSurfaceVariant: Color(0xFFCFC6B1),
        outline: Color(0xFF98917E),
        outlineVariant: Color(0xFF4E483A),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFFEAE4D5),
        onInverseSurface: Color(0xFF3F3B32),
        inversePrimary: Color(0xFF6D5727),
        surfaceTint: Color(0xFFD8BC7F),
      );
}

class _CreamPalette {
  const _CreamPalette();

  /// Page background
  final Color background = const Color(0xFFF7F1DF);

  /// Main reading area (cards)
  final Color readingArea = const Color(0xFFFAF5E8);

  /// Secondary background (inputs, chips)
  final Color secondaryBackground = const Color(0xFFF0E8D2);

  /// Dividers
  final Color divider = const Color(0xFFDED4BA);

  /// Primary text
  final Color primaryText = const Color(0xFF302D27);

  /// Secondary text
  final Color secondaryText = const Color(0xFF706A5E);

  /// Accent
  final Color accent = const Color(0xFFB58B3A);
}
