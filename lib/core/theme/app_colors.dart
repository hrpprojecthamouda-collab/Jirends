/// Design tokens — the Kurzgesagt-inspired palette. Warm, dark-first: a deep
/// blue-violet canvas with a small set of vivid, slightly-desaturated accent
/// pops. Raw colors live here; [AppTheme] maps them onto a Material 3
/// ColorScheme. Nothing outside the theme layer should hardcode a hex — pull
/// from `Theme.of(context).colorScheme` or the accent helpers below.
library;

import 'package:flutter/material.dart';

import '../../features/events/data/event.dart';

abstract final class AppColors {
  // ── Canvas / surfaces (layered deep navy-violet) ──────────────────────────
  static const bg = Color(0xFF13142A); // app background
  static const surface = Color(0xFF1C1E3A); // cards, nav rail
  static const surfaceHi = Color(0xFF262A52); // raised / hover / selected pill
  static const outline = Color(0xFF34386B); // hairlines, dividers, input border

  // ── Accents (the vivid pop) ───────────────────────────────────────────────
  static const violet = Color(0xFF7B6CF6); // primary / brand / selected nav
  static const blue = Color(0xFF4D9DE0); // secondary / info
  static const coral = Color(0xFFFF6B6B); // error / destructive
  static const teal = Color(0xFF2EC4B6); // success / confirmed
  static const yellow = Color(0xFFFFD166); // warning / highlight / "idea"

  // ── Text on dark ──────────────────────────────────────────────────────────
  static const ink = Color(0xFFF4F1EA); // primary text (warm off-white)
  static const inkMuted = Color(0xFFA9AAC9); // secondary text
  static const onAccent = Color(0xFF11122B); // text/icon on a filled accent

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
