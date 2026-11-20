import 'package:flutter/material.dart';

/// The palette of Y-Node for Android: a deep teal base with a copper accent.
/// Keeping the same values on the desktop makes the two clients look like one
/// product.
class AppColors {
  const AppColors._();

  static const Color teal = Color(0xFF0F766E);
  static const Color tealDeep = Color(0xFF052E2B);
  static const Color tealSoft = Color(0xFF14807A);
  static const Color copper = Color(0xFFD97706);
  static const Color copperDeep = Color(0xFFB45309);
  static const Color copperLight = Color(0xFFF59E0B);
  static const Color cream = Color(0xFFFFF7ED);

  static const Color online = Color(0xFF16A34A);
  static const Color offline = Color(0xFFDC2626);
  static const Color pending = Color(0xFFF59E0B);
}

class AppTheme {
  const AppTheme._();

  static final ThemeData _light = _build(Brightness.light);
  static final ThemeData _dark = _build(Brightness.dark);

  static ThemeData light() => _light;

  static ThemeData dark() => _dark;

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.teal,
          brightness: brightness,
        ).copyWith(
          secondary: isDark ? AppColors.copperLight : AppColors.copperDeep,
          secondaryContainer: isDark
              ? const Color(0xFF4A2A05)
              : const Color(0xFFFDEBD0),
          tertiary: isDark ? AppColors.tealSoft : AppColors.teal,
          surface: isDark ? const Color(0xFF0B1514) : const Color(0xFFF7FAF9),
          surfaceContainerLowest: isDark
              ? const Color(0xFF071010)
              : Colors.white,
          error: AppColors.offline,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark ? const Color(0xFF12201F) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.6),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.secondary),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF12201F) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
