/// Comment + reaction controllers for one event. Live providers for the thread
/// and the event's reactions, plus an action notifier for posting/deleting
/// comments and toggling reactions (on the event or a comment).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/comment.dart';
import '../data/comment_repository.dart';
import '../data/reaction.dart';
import '../data/reaction_repository.dart';

/// Live comment thread (oldest first).
final eventCommentsProvider =
    StreamProvider.family<List<Comment>, String>((ref, eventId) {
  return ref.watch(commentRepositoryProvider).watchComments(eventId);
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

  Future<bool> add(String eventId, String body) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _comments.addComment(eventId, body));
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
