/// Design tokens. These are no longer fixed values — they read through to the
/// [AppPalette] the user picked in Settings, so the whole app restyles when
/// that changes. Raw colors live in app_palette.dart; [AppTheme] maps these
/// onto a Material 3 ColorScheme. Nothing outside the theme layer should
/// hardcode a hex — pull from `Theme.of(context).colorScheme`,
/// `AppColors.primary`, or the accent helpers below.
///
/// These are getters rather than constants because the palette is chosen at
/// runtime. That means they can't be used in a `const` expression — if you hit
/// "not a constant expression", drop the `const` from that widget. The upside
/// is that every existing `AppColors.x` call site kept working untouched when
/// palettes were introduced.
///
/// Swapping the palette is done by [apply]; the widget tree then has to
/// rebuild for the new values to be painted, which paletteProvider handles.
library;

import 'package:flutter/material.dart';

import '../../features/events/data/event.dart';
import 'app_palette.dart';

abstract final class AppColors {
  static AppPalette _current = kDefaultPalette;

  /// The palette in force. Read this when you need the whole set (e.g. to
  /// build a ThemeData or render a palette preview).
  static AppPalette get current => _current;

  /// Switch palettes. Call from the palette controller, never from a widget —
  /// on its own this does NOT trigger a repaint.
  static void apply(AppPalette palette) => _current = palette;

  // ── Canvas / surfaces ─────────────────────────────────────────────────────
  static Color get bg => _current.bg;
  static Color get surface => _current.surface;
  static Color get surfaceHi => _current.surfaceHi;
  static Color get outline => _current.outline;

  // ── Accents ───────────────────────────────────────────────────────────────
  static Color get violet => _current.violet;
  static Color get blue => _current.blue;
  static Color get coral => _current.coral;
  static Color get teal => _current.teal;
  static Color get yellow => _current.yellow;

  /// Semantic alias: use this wherever the meaning is "brand / primary /
  /// selected", so the brand hue can change without a sweep. Named hues above
  /// are for places where the specific color IS the meaning (status, type).
  static Color get primary => _current.primary;

  // ── Text ──────────────────────────────────────────────────────────────────
  static Color get ink => _current.ink;
  static Color get inkMuted => _current.inkMuted;
  static Color get onAccent => _current.onAccent;

  /// Accent for an event type — keeps cards, pills, agenda dots consistent.
  static Color forEventType(EventType type) => switch (type) {
        EventType.trip => blue,
        EventType.dinner => teal,
        EventType.birthday => coral,
        EventType.meetup => violet,
      };

  /// Accent for a phase/status KEY. Keys are shared across types where the
  /// meaning matches (see event_types.sql), so we map by key, not by type.
  /// Unknown keys fall back to a neutral muted tone.
  static Color forPhaseKey(String? key) => switch (key) {
        'idea' => yellow,
        'planning' => blue,
        'booked' || 'confirmed' => violet,
        'on_trip' => teal,
        'done' || 'celebrated' => teal,
        'cancelled' => coral,
        _ => inkMuted,
      };
}
