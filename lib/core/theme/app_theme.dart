/// App theme. Dark-first, built from explicit [AppColors] tokens (NOT
/// ColorScheme.fromSeed — we want the exact Kurzgesagt shades to survive). Flat,
/// rounded, friendly. Light theme is deferred; `dark()` is the only real theme
/// for now and `light()` returns it so callers don't break.
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  /// Light theme is deferred — return the dark theme so the app is always the
  /// intended dark-first look regardless of platform brightness.
  static ThemeData light() => dark();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.violet,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.blue,
      onSecondary: AppColors.onAccent,
      tertiary: AppColors.teal,
      onTertiary: AppColors.onAccent,
      error: AppColors.coral,
      onError: AppColors.onAccent,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkMuted,
      surfaceContainerHighest: AppColors.surfaceHi,
      outline: AppColors.outline,
      outlineVariant: AppColors.outline,
      primaryContainer: AppColors.surfaceHi,
      onPrimaryContainer: AppColors.ink,
      secondaryContainer: AppColors.surfaceHi,
      onSecondaryContainer: AppColors.ink,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      dividerColor: AppColors.outline,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.violet,
          foregroundColor: AppColors.onAccent,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.blue),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.violet,
        foregroundColor: AppColors.onAccent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHi,
        labelStyle: const TextStyle(color: AppColors.inkMuted),
        hintStyle: const TextStyle(color: AppColors.inkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.violet, width: 2),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.surfaceHi,
        selectedIconTheme: IconThemeData(color: AppColors.violet),
        unselectedIconTheme: IconThemeData(color: AppColors.inkMuted),
        labelType: NavigationRailLabelType.none,
        useIndicator: true,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.violet
                  : AppColors.surfaceHi),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.onAccent
                  : AppColors.inkMuted),
          side: const WidgetStatePropertyAll(
              BorderSide(color: AppColors.outline)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceHi,
        contentTextStyle: TextStyle(color: AppColors.ink),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.outline, space: 1),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceHi,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: TextStyle(color: AppColors.ink),
      ),
    );
  }
}
