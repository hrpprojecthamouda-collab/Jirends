/// ReactionRepository — emoji reactions for one event and its comments. A
/// reaction targets the event (commentId null) or a comment. One reaction per
/// (target, emoji) per user, matching the partial unique indexes in schema.sql.
/// RLS scopes reads to members and writes to (user == self, member of event).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'reaction.dart';

class ReactionRepository {
  ReactionRepository(this._client);
  final SupabaseClient _client;

  Future<List<Reaction>> fetchReactions(String eventId) async {
    try {
      final rows =
          await _client.from('reactions').select().eq('event_id', eventId);
      return rows.map(Reaction.fromJson).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Stream<List<Reaction>> watchReactions(String eventId) {
    return _client
        .from('reactions')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .map((rows) => rows.map(Reaction.fromJson).toList());
  }

  /// Toggle the caller's reaction: if a matching row exists, delete it;
  /// otherwise insert. `commentId` null = reaction on the event itself.
  Future<void> toggleReaction(
    String eventId, {
    String? commentId,
    required String emoji,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      // Does the caller already have this exact reaction?
      var existing = _client
          .from('reactions')
          .select('id')
          .eq('event_id', eventId)
          .eq('user_id', uid)
          .eq('emoji', emoji);
      existing = commentId == null
          ? existing.isFilter('comment_id', null)
          : existing.eq('comment_id', commentId);
      final found = await existing.maybeSingle();

      if (found != null) {
        await _client.from('reactions').delete().eq('id', found['id'] as String);
      } else {
        await _client.from('reactions').insert({
          'event_id': eventId,
          'user_id': uid,
          'emoji': emoji,
          'comment_id': ?commentId,
        });
      }
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final reactionRepositoryProvider = Provider<ReactionRepository>((ref) {
  return ReactionRepository(ref.watch(supabaseClientProvider));
});
