/// CommentRepository — top-level comments for one event (each can be a
/// "discussion" with replies), plus the replies inside a discussion. RLS scopes
/// reads to members and writes to (author == self, member of event); any member
/// may set a comment's thread_title; delete to author or organizer. No client
/// visibility logic.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'comment.dart';

/// A top-level comment plus the number of replies in its discussion.
class RootComment {
  const RootComment({required this.comment, required this.replyCount});
  final Comment comment;
  final int replyCount;

  /// A discussion "exists" once there's at least one reply or a title.
  bool get hasDiscussion =>
      replyCount > 0 || (comment.threadTitle?.isNotEmpty ?? false);
}

class CommentRepository {
  CommentRepository(this._client);
  final SupabaseClient _client;

  /// Top-level comments for the event (oldest first), each with its reply count.
  Future<List<RootComment>> fetchComments(String eventId) async {
    try {
      final rows = await _client
          .from('comments')
          .select('*, author:profiles!comments_author_id_fkey(*)')
          .eq('event_id', eventId)
          .isFilter('parent_id', null)
          .order('created_at', ascending: true);
      final roots = rows.map(Comment.fromJson).toList();

      // Reply counts per root via the member-scoped RPC.
      final countRows =
          await _client.rpc('comment_reply_counts', params: {'p_event': eventId});
      final counts = <String, int>{
        for (final r in (countRows as List))
          (r as Map)['parent_id'] as String: (r['n'] as num).toInt(),
      };

      return [
        for (final c in roots)
          RootComment(comment: c, replyCount: counts[c.id] ?? 0),
      ];
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Live top-level comment list. Re-fetch on any change to the event's comments
  /// (covers new replies too, since they're rows in the same table).
  Stream<List<RootComment>> watchComments(String eventId) {
    return _client
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .asyncMap((_) => fetchComments(eventId));
  }

  /// Replies inside a discussion (oldest first), joined to author.
  Future<List<Comment>> fetchReplies(String rootId) async {
    try {
      final rows = await _client
          .from('comments')
          .select('*, author:profiles!comments_author_id_fkey(*)')
          .eq('parent_id', rootId)
          .order('created_at', ascending: true);
      return rows.map(Comment.fromJson).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Stream<List<Comment>> watchReplies(String rootId) {
    return _client
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('parent_id', rootId)
        .asyncMap((_) => fetchReplies(rootId));
  }

  /// Fetch a single comment (e.g. the discussion's root) by id.
  Future<Comment?> fetchComment(String id) async {
    try {
      final row = await _client
          .from('comments')
          .select('*, author:profiles!comments_author_id_fkey(*)')
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : Comment.fromJson(row);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Add a comment. With [parentId] set it's a reply inside that discussion.
  Future<void> addComment(String eventId, String body, {String? parentId}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      await _client.from('comments').insert({
        'event_id': eventId,
        'author_id': uid,
        'body': body.trim(),
        'parent_id': ?parentId,
      });
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Name (or rename) a discussion. Any member may do this (RLS). Pass null to
  /// clear it.
  Future<void> setThreadTitle(String rootId, String? title) async {
    try {
      await _client
          .from('comments')
          .update({'thread_title': (title?.trim().isEmpty ?? true) ? null : title!.trim()})
          .eq('id', rootId);
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
