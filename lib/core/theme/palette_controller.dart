/// Selected colour palette, persisted across launches.
///
/// Two-step by design: [AppColors.apply] swaps the values the whole app reads,
/// and the provider's state change rebuilds the tree so they get painted.
/// Doing only the first would change the tokens without repainting; doing only
/// the second would repaint the old colours.
///
/// The saved choice is loaded in `main()` BEFORE the first frame (see
/// [loadSavedPalette]) so the app never flashes the default palette and then
/// snap to the chosen one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_palette.dart';

const _prefsKey = 'palette_id';

/// Read the persisted palette and make it current. Call once, before runApp.
/// Never throws: if storage is unavailable the app just starts on the default.
Future<void> loadSavedPalette() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    AppColors.apply(paletteById(prefs.getString(_prefsKey)));
  } catch (_) {
    AppColors.apply(kDefaultPalette);
  }
}

class PaletteController extends Notifier<AppPalette> {
  @override
  AppPalette build() => AppColors.current;

  /// Switch palette and remember it. The state assignment is what rebuilds
  /// MaterialApp (and therefore everything reading [AppColors]).
  Future<void> select(AppPalette palette) async {
    if (palette.id == state.id) return;
    AppColors.apply(palette);
    state = palette;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, palette.id);
    } catch (_) {
      // Persisting failed (storage unavailable) — the choice still applies for
      // this session, it just won't survive a restart. Not worth an error UI.
    }
  }
}

final paletteProvider = NotifierProvider<PaletteController, AppPalette>(
  PaletteController.new,
);
