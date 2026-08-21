/// ReactionRepository — emoji reactions for one event and its comments. A
/// reaction targets the event (commentId null) or a comment. **One reaction per
/// user per target**: choosing a different emoji replaces the previous one,
/// choosing the current one clears it. RLS scopes reads to members and writes
/// to (user == self, member of event).
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

  /// Live reactions for the event. Re-fetches the authoritative list on every
  /// change rather than trusting the incrementally-maintained stream payload —
  /// same pattern as CommentRepository.watchComments.
  ///
  /// This matters for DELETEs: realtime only sends the columns in the table's
  /// REPLICA IDENTITY, so `reactions` is set to FULL (see schema.sql) to make
  /// the `event_id` filter match on delete. Re-fetching keeps the UI correct
  /// even if a payload arrives partial, so un-reacting always drops the count.
  Stream<List<Reaction>> watchReactions(String eventId) {
    return _client
        .from('reactions')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .asyncMap((_) => fetchReactions(eventId));
  }

  /// Set the caller's single reaction on a target. Tapping the emoji you're
  /// already on clears it; tapping a different one replaces it. `commentId`
  /// null = reaction on the event itself.
  ///
  /// Clears ALL of the caller's existing rows for the target rather than just
  /// one, so a user who reacted several times under the old
  /// multiple-reactions-allowed rules collapses to a single reaction the next
  /// time they touch it (self-healing — see the dedupe migration note in
  /// schema.sql).
  Future<void> setMyReaction(
    String eventId, {
    String? commentId,
    required String emoji,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      var query = _client
          .from('reactions')
          .select('id, emoji')
          .eq('event_id', eventId)
          .eq('user_id', uid);
      query = commentId == null
          ? query.isFilter('comment_id', null)
          : query.eq('comment_id', commentId);
      final mine = await query;

      final alreadyOnThisEmoji = mine.any((r) => r['emoji'] == emoji);

      if (mine.isNotEmpty) {
        await _client
            .from('reactions')
            .delete()
            .inFilter('id', [for (final r in mine) r['id'] as String]);
      }

      // Tapping your current emoji is "un-react": stop after clearing.
      if (alreadyOnThisEmoji) return;

      await _client.from('reactions').insert({
        'event_id': eventId,
        'user_id': uid,
        'emoji': emoji,
        'comment_id': ?commentId,
      });
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Every reaction on one target, joined to the reacting user's profile — for
  /// the "who reacted" sheet. A separate query because realtime `.stream()`
  /// cannot join. Still RLS-scoped: only members read an event's reactions.
  Future<List<Reaction>> fetchReactionsWithUsers(
    String eventId, {
    String? commentId,
  }) async {
    try {
      var query = _client
          .from('reactions')
          .select('*, user:profiles!reactions_user_id_fkey(*)')
          .eq('event_id', eventId);
      query = commentId == null
          ? query.isFilter('comment_id', null)
          : query.eq('comment_id', commentId);
      final rows = await query.order('created_at', ascending: true);
      return rows.map(Reaction.fromJson).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final reactionRepositoryProvider = Provider<ReactionRepository>((ref) {
  return ReactionRepository(ref.watch(supabaseClientProvider));
});
