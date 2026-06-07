/// CommentRepository — comments for one event, joined to author profiles. RLS
/// scopes reads to members and writes to (author == self, member of event);
/// delete to author or organizer. No client visibility logic.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'comment.dart';

class CommentRepository {
  CommentRepository(this._client);
  final SupabaseClient _client;

  Future<List<Comment>> fetchComments(String eventId) async {
    try {
      final rows = await _client
          .from('comments')
          .select('*, author:profiles!comments_author_id_fkey(*)')
          .eq('event_id', eventId)
          .order('created_at', ascending: true);
      return rows.map(Comment.fromJson).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Live comment thread (oldest first). Re-fetch joined rows on any change.
  Stream<List<Comment>> watchComments(String eventId) {
    return _client
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .asyncMap((_) => fetchComments(eventId));
  }

  Future<void> addComment(String eventId, String body) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      await _client.from('comments').insert({
        'event_id': eventId,
        'author_id': uid,
        'body': body.trim(),
      });
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> deleteComment(String commentId) async {
    try {
      await _client.from('comments').delete().eq('id', commentId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final commentRepositoryProvider = Provider<CommentRepository>((ref) {
  return CommentRepository(ref.watch(supabaseClientProvider));
});
