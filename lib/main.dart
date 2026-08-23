import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/env/env.dart';
import 'core/i18n/fallback_material_localizations.dart';
import 'core/i18n/locale_controller.dart';
import 'core/supabase/supabase_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/palette_controller.dart';
import 'l10n/app_localizations.dart';
import 'core/util/deep_links.dart';
import 'routing/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialise locale-aware date formatting used by the agenda/calendar views.
  await initializeDateFormatting();

  if (!Env.isConfigured) {
    // Fail loudly rather than connecting to a placeholder.
    runApp(const _MisconfiguredApp());
    return;
  }

  await initSupabase();
  // Restore the chosen palette before the first frame, so the app never shows
  // the default and then snaps to the saved one.
  await loadSavedPalette();
  runApp(const ProviderScope(child: JirendsApp()));
}

class JirendsApp extends ConsumerStatefulWidget {
  const JirendsApp({super.key});

  @override
  ConsumerState<JirendsApp> createState() => _JirendsAppState();
}

class _JirendsAppState extends ConsumerState<JirendsApp> {
  @override
  void initState() {
    super.initState();
    // Invite links arrive through app_links (see deep_links.dart for why the
    // manifest flag alone is not enough). Start after the first frame so the
    // router exists before a cold-start link tries to navigate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deepLinkServiceProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    // Watching the palette is what rebuilds the whole tree when the user picks
    // a different one in Settings.
    final palette = ref.watch(paletteProvider);
    return MaterialApp.router(
      // Re-keying on the palette is what makes a theme change actually repaint.
      // Widgets read colours from AppColors — a plain global, not an
      // InheritedWidget — so a new ThemeData does not mark them dirty, and most
      // screens are `const`, which makes Flutter skip rebuilding them entirely
      // (Element.update short-circuits on an identical widget). Keying a
      // subtree *inside* the app doesn't help either: WidgetsApp gives its
      // Navigator a GlobalKey, so the whole route subtree is moved rather than
      // rebuilt. Replacing the MaterialApp is what forces every screen to
      // re-read its colours. The route stack lives in the GoRouter (held by
      // Riverpod, outside this widget), so the current page is restored.
      key: ValueKey(palette.id),
      title: 'Jirends',
      debugShowCheckedModeBanner: false,
      // One theme, built from the chosen palette. themeMode follows the
      // palette's own brightness rather than the device, so the picked look is
      // exactly what you get.
      theme: AppTheme.of(palette),
      themeMode: palette.brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        // 'tn' has no framework bundle; these fold it onto 'en' for Material/
        // Cupertino/Widgets while AppLocalizations still serves 'tn' strings.
        ...tnAwareFrameworkDelegates,
      ],
      routerConfig: router,
    );
  }
}

/// Shown when env.dart still has placeholder values.
class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Supabase is not configured.\n\n'
              'Copy lib/core/env/env.example.dart to env.dart and fill in your '
              'project URL and anon key.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
