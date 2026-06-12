/// Design tokens — the "sunset" palette. Warm, dark-first: a deep aubergine
/// canvas with a peach-orange primary and a small set of vivid accent pops.
/// Raw colors live here; [AppTheme] maps them onto a Material 3 ColorScheme.
/// Nothing outside the theme layer should hardcode a hex — pull from
/// `Theme.of(context).colorScheme`, `AppColors.primary`, or the accent helpers
/// below.
library;

import 'package:flutter/material.dart';

import '../../features/events/data/event.dart';

abstract final class AppColors {
  // ── Canvas / surfaces (layered deep aubergine) ────────────────────────────
  static const bg = Color(0xFF1F1426); // app background
  static const surface = Color(0xFF2A1B33); // cards, nav rail
  static const surfaceHi = Color(0xFF3A2745); // raised / hover / selected pill
  static const outline = Color(0xFF4F3A5C); // hairlines, dividers, input border

  // ── Accents (the vivid pop) ───────────────────────────────────────────────
  static const peach = Color(0xFFFF9E7D); // sunset primary / brand / selected
  static const violet = Color(0xFF7B6CF6); // secondary accent
  static const blue = Color(0xFF4D9DE0); // info
  static const coral = Color(0xFFFF6B6B); // error / destructive ONLY
  static const teal = Color(0xFF2EC4B6); // success / confirmed
  static const yellow = Color(0xFFFFD166); // warning / highlight / "idea"

  /// Semantic alias: use this wherever the meaning is "brand / primary /
  /// selected", so the brand hue can change without a sweep. Named hues above
  /// are for places where the specific color IS the meaning (status, type).
  static const primary = peach;

  // ── Text on dark ──────────────────────────────────────────────────────────
  static const ink = Color(0xFFF7EFE9); // primary text (warm off-white)
  static const inkMuted = Color(0xFFC0ABBE); // secondary text
  static const onAccent = Color(0xFF221019); // text/icon on a filled accent

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
