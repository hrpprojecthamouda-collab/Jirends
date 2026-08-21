/// ProfileRepository — reads/writes public.profiles. Used by the onboarding
/// gate to check whether the user has a handle and to set one, and by the
/// profile screen to set the user's photo.
///
/// Avatar bytes live in the public `avatars` bucket under `{user_id}/…`, with
/// the resulting URL stored in profiles.avatar_url (see avatars.sql for why the
/// bucket is public and why that adds no visibility path).
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'profile.dart';

const _avatarBucket = 'avatars';

/// Matches the bucket's own `file_size_limit`. Checked client-side too so an
/// oversized pick fails immediately with a sentence the user can act on,
/// rather than after uploading several megabytes.
const kAvatarMaxBytes = 5 * 1024 * 1024;

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

  /// Upload [bytes] as the signed-in user's photo and point avatar_url at it.
  ///
  /// Bytes first, row second — the same order as attachments, so avatar_url
  /// never names an object that isn't there yet. The filename is unique per
  /// upload rather than a fixed `avatar.png`: a stable URL would be served
  /// stale from the CDN cache for as long as it felt like it, and a new photo
  /// that doesn't appear reads as a broken feature.
  Future<Profile> setAvatar({
    required Uint8List bytes,
    required String extension,
    String? mimeType,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    if (bytes.length > kAvatarMaxBytes) {
      throw const ValidationFailure('That image is too large (max 5 MB).');
    }

    final unique = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final path = '$uid/$unique.$extension';
    final storage = _client.storage.from(_avatarBucket);

    try {
      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: mimeType, upsert: false),
      );
      final url = storage.getPublicUrl(path);
      final row = await _table
          .update({'avatar_url': url})
          .eq('id', uid)
          .select()
          .single();
      // Only once the new photo is live: dropping the old one first would
      // leave the user faceless if the upload then failed.
      await _sweepOldAvatars(uid, keep: path);
      return Profile.fromJson(row);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Clear the photo and delete the bytes behind it.
  Future<Profile> removeAvatar() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      final row = await _table
          .update({'avatar_url': null})
          .eq('id', uid)
          .select()
          .single();
      await _sweepOldAvatars(uid);
      return Profile.fromJson(row);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Delete every object in the user's own avatar folder except [keep].
  ///
  /// Best-effort by design: an orphaned object is invisible, capped at 5MB and
  /// sits in a folder only its owner can write to, so failing to tidy up is
  /// never a reason to fail a photo change the user has already seen succeed.
  Future<void> _sweepOldAvatars(String uid, {String? keep}) async {
    try {
      final storage = _client.storage.from(_avatarBucket);
      final existing = await storage.list(path: uid);
      final stale = [
        for (final f in existing)
          if ('$uid/${f.name}' != keep) '$uid/${f.name}',
      ];
      if (stale.isNotEmpty) await storage.remove(stale);
    } catch (_) {
      // Deliberately swallowed — see above.
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
