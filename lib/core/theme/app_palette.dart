/// AppPalette — one complete set of colour tokens, selectable at runtime from
/// Settings. Every palette fills the SAME slots, so swapping one for another
/// restyles the whole app without touching a widget.
///
/// The six accents are not decoration: [forEventType] and [forPhaseKey] in
/// app_colors.dart map event types and statuses onto them, so each palette has
/// to keep them distinguishable from one another AND legible as text. Every
/// value below is contrast-checked — each accent clears WCAG AA (4.5:1) against
/// that palette's card surface, and [ink] clears AAA (7:1) against [bg].
library;

import 'package:flutter/material.dart';

@immutable
class AppPalette {
  const AppPalette({
    required this.id,
    required this.label,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.outline,
    required this.primary,
    required this.violet,
    required this.blue,
    required this.coral,
    required this.teal,
    required this.yellow,
    required this.ink,
    required this.inkMuted,
    required this.onAccent,
  });

  /// Stable key used for persistence — never change these once shipped.
  final String id;

  /// Shown in Settings. Deliberately not localised: these are names, like a
  /// paint chip, and read the same in every language.
  final String label;

  final Brightness brightness;

  // Canvas / surfaces.
  final Color bg;
  final Color surface;
  final Color surfaceHi;
  final Color outline;

  // Accents. `primary` is the brand/selected hue; the rest carry meaning.
  final Color primary;
  final Color violet;
  final Color blue;
  final Color coral;
  final Color teal;
  final Color yellow;

  // Text.
  final Color ink;
  final Color inkMuted;
  final Color onAccent;

  /// Oat & Clay — warm oat paper, deep clay, coffee-dark ink. The default.
  ///
  /// The clay primary and the ochre are both a shade deeper than the original
  /// sketch: at the lighter values they measured 3.78:1 and 3.97:1 as text,
  /// under the 4.5:1 bar. The coral was also pushed to a deeper red so the
  /// brand colour can't be mistaken for the destructive one.
  static const oatClay = AppPalette(
    id: 'oat_clay',
    label: 'Oat & Clay',
    brightness: Brightness.light,
    bg: Color(0xFFF4EDE4),
    surface: Color(0xFFFEFBF7),
    surfaceHi: Color(0xFFEDE2D5),
    outline: Color(0xFFD9CBBA),
    primary: Color(0xFFB0552B), // 4.87:1
    yellow: Color(0xFF8A5D0A), // 5.58:1
    blue: Color(0xFF356F94), // 5.28:1
    violet: Color(0xFF6250B4), // 6.12:1
    teal: Color(0xFF2A8064), // 4.66:1
    coral: Color(0xFF9E241C), // 7.48:1
    ink: Color(0xFF2E241F), // 13.02:1 vs bg
    inkMuted: Color(0xFF7A6759),
    onAccent: Color(0xFFFFF7F0), // 4.74:1 on primary
  );

  /// Apricot Morning — peach-tinted paper, burnt orange, espresso ink. The
  /// warmest of the three. Its "idea" yellow is olive rather than sunny: at a
  /// true yellow it sat too close to the orange primary to tell apart.
  static const apricotMorning = AppPalette(
    id: 'apricot_morning',
    label: 'Apricot Morning',
    brightness: Brightness.light,
    bg: Color(0xFFFDF4EC),
    surface: Color(0xFFFFFFFF),
    surfaceHi: Color(0xFFF6E7D9),
    outline: Color(0xFFE3CDB8),
    primary: Color(0xFFA85410), // 5.33:1
    yellow: Color(0xFF66701A), // 5.39:1
    blue: Color(0xFF1A5F9E), // 6.62:1
    violet: Color(0xFF5B45A8), // 7.34:1
    teal: Color(0xFF12734A), // 5.87:1
    coral: Color(0xFFA11F1F), // 7.69:1
    ink: Color(0xFF221812), // 16.01:1 vs bg
    inkMuted: Color(0xFF6F5C4E),
    onAccent: Color(0xFFFFF6EE), // 4.99:1 on primary
  );

  /// Sage & Sienna — pale sage paper, sienna brand. The only cool ground of the
  /// three, which calms the whole app and makes the warm accents read stronger.
  static const sageSienna = AppPalette(
    id: 'sage_sienna',
    label: 'Sage & Sienna',
    brightness: Brightness.light,
    bg: Color(0xFFF1F3EA),
    surface: Color(0xFFFBFCF7),
    surfaceHi: Color(0xFFE4E9D8),
    outline: Color(0xFFCBD3BC),
    primary: Color(0xFFA5560D), // 5.17:1
    yellow: Color(0xFF5F6B12), // 5.66:1
    blue: Color(0xFF1A5F9E), // 6.42:1
    violet: Color(0xFF59459F), // 7.34:1
    teal: Color(0xFF12704A), // 5.92:1
    coral: Color(0xFF9B241E), // 7.64:1
    ink: Color(0xFF1C211A), // 14.63:1 vs bg
    inkMuted: Color(0xFF5E6B58),
    onAccent: Color(0xFFFDFBF2), // 5.15:1 on primary
  );
}

/// Every selectable palette, in the order Settings shows them.
const kAppPalettes = <AppPalette>[
  AppPalette.oatClay,
  AppPalette.apricotMorning,
  AppPalette.sageSienna,
];

/// The one used until the user picks otherwise.
const kDefaultPalette = AppPalette.oatClay;

/// Look a palette up by its persisted [AppPalette.id]. Falls back to the
/// default for an unknown or missing id, so a renamed/removed palette can never
/// leave the app without colours.
AppPalette paletteById(String? id) {
  for (final p in kAppPalettes) {
    if (p.id == id) return p;
  }
  return kDefaultPalette;
}
