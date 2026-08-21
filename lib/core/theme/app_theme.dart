/// App theme, built from explicit [AppPalette] tokens (NOT ColorScheme.fromSeed
/// — we want the exact chosen shades to survive). Flat, rounded, friendly;
/// Baloo 2 for the type.
///
/// The palette is chosen at runtime in Settings, so [of] takes one and returns
/// the matching ThemeData. Nothing here is `const` any more: a const
/// expression can't read a value that changes.
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_palette.dart';

abstract final class AppTheme {
  /// Material's type scale (16 body, 14 secondary, 11 caption…) is drawn for
  /// Roboto. We render it in Baloo 2, which is optically smaller at the same
  /// nominal size — measured from the two font binaries themselves:
  ///
  ///                 x-height    cap-height
  ///   Roboto         0.528 em    0.711 em
  ///   Baloo 2        0.460 em    0.602 em
  ///
  /// So Baloo 2 at 16sp puts the same ink on screen as Roboto at ~13.9sp, and
  /// every screen ends up reading a tier smaller than Material intended. This
  /// factor (0.528 / 0.460) puts the apparent size back where the scale says
  /// it should be. It is deliberately ONE number: if the app still reads small
  /// (or now reads large), turn this, don't sprinkle fontSize overrides.
  static const double _opticalScale = 1.15;

  /// Material's scale also ships letter-spacing tuned for Roboto — +0.5 on
  /// bodyLarge, +0.25 on bodyMedium, and so on. Baloo 2 is a wide, round face
  /// that already carries generous sidebearings, so that tracking is added on
  /// top of spacing the font had built in.
  ///
  /// It is not free: measured from the font binary, +0.5 across a 116-character
  /// description costs 58dp — 6.5% of every line's width — which is text column
  /// spent on air, and on a phone that is whole words pushed to the next line.
  /// Zeroing it hands spacing back to the typeface that was designed for it.
  ///
  /// The uppercase card labels want the opposite and set their own
  /// `letterSpacing: 1.1` at the call site, which wins over this.
  static const double _letterSpacingFactor = 0.0;

  /// Build the theme for [palette]. Also applies it to [AppColors] so the two
  /// can never disagree — a widget reading `AppColors.bg` always matches the
  /// ThemeData it's being painted under.
  static ThemeData of(AppPalette palette) {
    AppColors.apply(palette);
    final isDark = palette.brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: palette.brightness,
      primary: palette.primary,
      onPrimary: palette.onAccent,
      secondary: palette.violet,
      onSecondary: palette.onAccent,
      tertiary: palette.teal,
      onTertiary: palette.onAccent,
      error: palette.coral,
      onError: palette.onAccent,
      surface: palette.surface,
      onSurface: palette.ink,
      onSurfaceVariant: palette.inkMuted,
      surfaceContainerHighest: palette.surfaceHi,
      outline: palette.outline,
      outlineVariant: palette.outline,
      primaryContainer: palette.surfaceHi,
      onPrimaryContainer: palette.ink,
      secondaryContainer: palette.surfaceHi,
      onSecondaryContainer: palette.ink,
    );

    // The optical correction is applied to the TYPOGRAPHY GEOMETRY, not to
    // `base.textTheme`. ThemeData's textTheme carries colours only — every
    // fontSize in it is null until `ThemeData.localize` merges the geometry for
    // the locale's script at build time. Scaling the textTheme therefore both
    // asserts (TextStyle.apply requires a non-null fontSize) and would be
    // overwritten. The geometry is where the numbers actually live.
    final typography = Typography.material2021(
      platform: defaultTargetPlatform,
      colorScheme: scheme,
    ).copyWith(
      englishLike: Typography.englishLike2021.apply(
        fontSizeFactor: _opticalScale,
        letterSpacingFactor: _letterSpacingFactor,
      ),
      dense: Typography.dense2021.apply(
        fontSizeFactor: _opticalScale,
        letterSpacingFactor: _letterSpacingFactor,
      ),
      tall: Typography.tall2021.apply(
        fontSizeFactor: _opticalScale,
        letterSpacingFactor: _letterSpacingFactor,
      ),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      colorScheme: scheme,
      typography: typography,
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.bg,
      dividerColor: palette.outline,
      // On a light ground the default ripple is nearly invisible; darken it.
      splashColor: isDark ? null : palette.primary.withValues(alpha: .10),
    );

    // Baloo 2 everywhere — rounded and chunky, for a friendly, playful feel.
    // Headings are ExtraBold, labels sturdy. Sizes are the Material scale
    // times [_opticalScale] (see below), except headlineSmall which is set
    // outright so the event title reads as the page's anchor.
    final baloo = GoogleFonts.baloo2TextTheme(base.textTheme).apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );
    final textTheme = baloo.copyWith(
      // Event title: 28, set outright and NOT scaled with the rest. Baloo 2 is
      // wide, so this is as large as a multi-word title can go before wrapping
      // on a phone — the optical correction would push it to 32 and wrap it.
      headlineSmall: baloo.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 28,
      ),
      titleLarge: baloo.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: baloo.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      labelLarge: baloo.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      labelMedium: baloo.labelMedium?.copyWith(fontWeight: FontWeight.w700),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
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
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onAccent,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.blue),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onAccent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHi,
        labelStyle: TextStyle(color: AppColors.inkMuted),
        hintStyle: TextStyle(color: AppColors.inkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.surfaceHi,
        selectedIconTheme: IconThemeData(color: AppColors.primary),
        unselectedIconTheme: IconThemeData(color: AppColors.inkMuted),
        labelType: NavigationRailLabelType.none,
        useIndicator: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.surfaceHi,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.inkMuted,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => GoogleFonts.baloo2(
              // Hand-written rather than read off the TextTheme, so it needs
              // the optical correction applied by hand too.
              fontSize: 12 * _opticalScale,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.inkMuted,
            )),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.surfaceHi),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.onAccent
                  : AppColors.inkMuted),
          side: WidgetStatePropertyAll(
              BorderSide(color: AppColors.outline)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHi,
        contentTextStyle: TextStyle(color: AppColors.ink),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(color: AppColors.outline, space: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceHi,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: TextStyle(color: AppColors.ink),
      ),
    );
  }
}
