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

/// Live replies inside one discussion (root comment id).
final repliesProvider =
    StreamProvider.family<List<Comment>, String>((ref, rootId) {
  return ref.watch(commentRepositoryProvider).watchReplies(rootId);
});

/// The discussion's root comment by id (for the discussion screen header).
final commentByIdProvider =
    FutureProvider.family<Comment?, String>((ref, id) {
  return ref.watch(commentRepositoryProvider).fetchComment(id);
});

/// Live reactions for the event and all its comments.
final eventReactionsProvider =
    StreamProvider.family<List<Reaction>, String>((ref, eventId) {
  return ref.watch(reactionRepositoryProvider).watchReactions(eventId);
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

  Future<void> delete(String commentId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _comments.deleteComment(commentId));
  }

  Future<void> toggleReaction(
    String eventId, {
    String? commentId,
    required String emoji,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        _reactions.toggleReaction(eventId, commentId: commentId, emoji: emoji));
  }
}

final commentActionsControllerProvider =
    AsyncNotifierProvider<CommentActionsController, void>(
        CommentActionsController.new);
