/// ProfileRepository — reads/writes public.profiles. Used by the onboarding
/// gate to check whether the user has a handle and to set one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('profiles');

  /// The signed-in user's profile, or null if there is no session.
  Future<Profile?> fetchMyProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _table.select().eq('id', uid).maybeSingle();
      return row == null ? null : Profile.fromJson(row);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Set (or change) the handle. Maps a unique-violation to a friendly
  /// "handle taken" [ConflictFailure].
  Future<Profile> setHandle({required String nickname, required String tagline}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      final row = await _table
          .update({'nickname': nickname, 'tagline': tagline})
          .eq('id', uid)
          .select()
          .single();
      return Profile.fromJson(row);
    } catch (e) {
      final f = mapToFailure(e);
      // mapToFailure already turns 23505 into ConflictFailure('handle taken').
      throw f;
    }
  }

  /// Realtime-friendly stream of my profile (used by the onboarding gate so the
  /// app reacts the moment a handle is set).
  Stream<Profile?> watchMyProfile() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return Stream.value(null);
    return _table
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .map((rows) => rows.isEmpty ? null : Profile.fromJson(rows.first));
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

/// The current user's profile as an async value. Auto-refreshes when auth
/// state changes (so signing in/out re-fetches).
final myProfileProvider = FutureProvider<Profile?>((ref) async {
  // Re-run whenever the session changes.
  ref.watch(currentSessionProvider);
  return ref.watch(profileRepositoryProvider).fetchMyProfile();
});
