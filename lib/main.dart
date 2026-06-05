import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env/env.dart';
import 'core/supabase/supabase_providers.dart';
import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    return MaterialApp.router(
      title: 'Jirends',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
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
