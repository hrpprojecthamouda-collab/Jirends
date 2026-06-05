/// Environment configuration — TEMPLATE.
///
/// Copy this file to `env.dart` (which is gitignored) and fill in the real
/// values. The anon key is a public client key — RLS in Postgres is the real
/// security boundary — but we keep the concrete file out of git so the repo
/// stays free of project-specific config.
///
///   cp lib/core/env/env.example.dart lib/core/env/env.dart
///
/// Find these under: Supabase Dashboard → Project Settings → API.
library;

abstract final class Env {
  /// e.g. https://YOUR_PROJECT_REF.supabase.co
  static const String supabaseUrl = 'https://YOUR_PROJECT_REF.supabase.co';

  /// The "anon" / "public" API key (a JWT starting with "eyJ...").
  static const String supabaseAnonKey = 'YOUR_ANON_PUBLIC_KEY';
}
