import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/env/env.dart';
import 'core/i18n/fallback_material_localizations.dart';
import 'core/i18n/locale_controller.dart';
import 'core/supabase/supabase_providers.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
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
  runApp(const ProviderScope(child: JirendsApp()));
}

class JirendsApp extends ConsumerWidget {
  const JirendsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'Jirends',
      debugShowCheckedModeBanner: false,
      // Dark-first; light() returns the dark theme for now.
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
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
