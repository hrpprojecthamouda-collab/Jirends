/// FriendRepository — the caller's address book. A "friend" for the UI is just
/// the [Profile] of someone in your `friends` table, so we reuse Profile
/// rather than introduce a new model.
///
/// Friendship is mutual (see social_layer.sql): adding someone by handle adds
/// you to each other's books in the same call, no request/accept. Removing is
/// one-sided — it only ever deletes your own row. `is_friend` / the friends
/// RLS already scope everything to the caller, so there is no visibility
/// logic here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../auth/data/profile.dart';

class FriendRepository {
  FriendRepository(this._client);
  final SupabaseClient _client;

  /// One-shot fetch of the caller's friends as profiles, alphabetised by handle.
  /// Joins friends -> profiles in a single PostgREST embedded select.
  Future<List<Profile>> fetchFriends() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final rows = await _client
          .from('friends')
          .select('friend:profiles!friends_friend_id_fkey(*)')
          .eq('owner_id', uid);
      final profiles = rows
          .map((r) => Profile.fromJson(r['friend'] as Map<String, dynamic>))
          .toList()
        ..sort((a, b) =>
            (a.handle ?? '').toLowerCase().compareTo((b.handle ?? '').toLowerCase()));
      return profiles;
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// A stream that re-emits whenever the caller's `friends` rows change, so the
  /// list can refresh on add/remove. The stream itself only carries ids, so we
  /// re-fetch the joined profiles on each change.
  Stream<List<Profile>> watchFriends() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return Stream.value(const []);
    return _client
        .from('friends')
        .stream(primaryKey: ['owner_id', 'friend_id'])
        .eq('owner_id', uid)
        .asyncMap((_) => fetchFriends());
  }

  /// Add a friend by their `nickname#tagline` handle. Calls the SECURITY DEFINER
  /// RPC which validates the handle, resolves the profile, and writes BOTH
  /// directions (mutual — the target sees the caller back immediately, no
  /// accept step). Returns the friend's id. Maps a malformed/unknown handle
  /// and self-add to typed failures.
  Future<String> addByHandle(String handle) async {
    try {
      final id = await _client
          .rpc('add_friend_by_handle', params: {'p_handle': handle.trim()});
      return id as String;
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Remove someone from the caller's address book. Deliberately one-sided
  /// (unlike adding): only your row is deleted, the other person keeps you in
  /// their own book unless they remove you too. RLS lets you delete only your
  /// own friends rows.
  Future<void> removeFriend(String friendId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      await _client
          .from('friends')
          .delete()
          .eq('owner_id', uid)
          .eq('friend_id', friendId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return FriendRepository(ref.watch(supabaseClientProvider));
});
