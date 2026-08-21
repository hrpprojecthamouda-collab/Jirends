/// Comment + reaction controllers for one event. Live providers for the
/// top-level comments (each a possible discussion), the replies inside a
/// discussion, and the event's reactions, plus an action notifier for posting /
/// replying / deleting / naming a discussion / toggling reactions.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/comment.dart';
import '../data/comment_repository.dart';
import '../data/reaction.dart';
import '../data/reaction_repository.dart';

/// Live top-level comments (oldest first), each with its reply count.
final eventCommentsProvider =
    StreamProvider.family<List<RootComment>, String>((ref, eventId) {
  return ref.watch(commentRepositoryProvider).watchComments(eventId);
});

/// Live replies inside one discussion (root comment id). autoDispose: keyed
/// per root comment, so without it every discussion ever opened would hold a
/// realtime channel for the rest of the session.
final repliesProvider =
    StreamProvider.autoDispose.family<List<Comment>, String>((ref, rootId) {
  return ref.watch(commentRepositoryProvider).watchReplies(rootId);
});

/// The discussion's root comment by id (for the discussion screen header).
/// autoDispose so reopening a discussion re-fetches (picks up another member's
/// rename instead of serving a session-cached copy).
final commentByIdProvider =
    FutureProvider.autoDispose.family<Comment?, String>((ref, id) {
  return ref.watch(commentRepositoryProvider).fetchComment(id);
});

/// Live reactions for the event and all its comments.
final eventReactionsProvider =
    StreamProvider.family<List<Reaction>, String>((ref, eventId) {
  return ref.watch(reactionRepositoryProvider).watchReactions(eventId);
});

/// Identifies one reaction target: the event itself ([commentId] null) or a
/// specific comment. A record so Riverpod's family gets structural equality.
typedef ReactionTarget = ({String eventId, String? commentId});

/// Everyone who reacted to one target, joined to their profiles — backs the
/// "who reacted" sheet. autoDispose: it's opened on demand and should re-fetch
/// next time rather than serve a stale roster.
final reactionUsersProvider = FutureProvider.autoDispose
    .family<List<Reaction>, ReactionTarget>((ref, target) {
  return ref.watch(reactionRepositoryProvider).fetchReactionsWithUsers(
        target.eventId,
        commentId: target.commentId,
      );
});

class CommentActionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  CommentRepository get _comments => ref.read(commentRepositoryProvider);
  ReactionRepository get _reactions => ref.read(reactionRepositoryProvider);

  /// Post a top-level comment.
  Future<bool> add(String eventId, String body) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _comments.addComment(eventId, body));
    return !state.hasError;
  }

  /// Post a reply inside a discussion (rootId = the top-level comment).
  Future<bool> reply(String eventId, String rootId, String body) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _comments.addComment(eventId, body, parentId: rootId));
    return !state.hasError;
  }

  /// Name / rename a discussion (any member). Pass null to clear.
  Future<bool> setThreadTitle(String rootId, String? title) async {
    state = const AsyncLoading();
    state =
        await AsyncValue.guard(() => _comments.setThreadTitle(rootId, title));
    return !state.hasError;
  }

  Future<bool> delete(String commentId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _comments.deleteComment(commentId));
    return !state.hasError;
  }

  /// Set the caller's single reaction on a target (see
  /// [ReactionRepository.setMyReaction]): a different emoji replaces the
  /// current one, the same emoji clears it.
  Future<void> setMyReaction(
    String eventId, {
    String? commentId,
    required String emoji,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        _reactions.setMyReaction(eventId, commentId: commentId, emoji: emoji));
    // Refresh the who-reacted roster so a sheet opened right after a tap
    // reflects the change (the realtime stream drives the chips, not this).
    ref.invalidate(
        reactionUsersProvider((eventId: eventId, commentId: commentId)));
  }
}

final commentActionsControllerProvider =
    AsyncNotifierProvider<CommentActionsController, void>(
        CommentActionsController.new);
