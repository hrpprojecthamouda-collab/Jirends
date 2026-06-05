/// Supabase bootstrap + the root providers other layers build on.
///
/// `Supabase.initialize` is called once in main(); here we just expose the
/// already-initialised client and the auth-state stream to Riverpod. Nothing
/// above the repository layer should import supabase_flutter directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env/env.dart';

/// Initialise the Supabase singleton. Call once, before runApp.
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: Env.supabaseUrl,
    // Newer `sb_publishable_…` key format; goes in the publishableKey slot.
    publishableKey: Env.supabaseAnonKey,
    // Persist the session so users stay logged in across launches.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}

/// The initialised client. Overridden-free: reads the global singleton.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Convenience: the auth client.
final goTrueClientProvider = Provider<GoTrueClient>((ref) {
  return ref.watch(supabaseClientProvider).auth;
});

/// Stream of auth state changes (sign-in, sign-out, token refresh). The router
/// listens to this to redirect between the auth gate and the app.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(goTrueClientProvider).onAuthStateChange;
});

/// The current [Session], or null if signed out. Recomputed on every auth event.
final currentSessionProvider = Provider<Session?>((ref) {
  // Seed with whatever's already there (e.g. restored on launch), then track
  // changes via the stream.
  final current = ref.watch(goTrueClientProvider).currentSession;
  final streamed = ref.watch(authStateChangesProvider).value?.session;
  return streamed ?? current;
});

/// The current user's id, or null. Most repositories need this.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentSessionProvider)?.user.id;
});
