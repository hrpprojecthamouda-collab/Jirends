/// Comments tab — the event's thread plus a compose box. Each comment shows its
/// author, body, time, and a reaction bar. You can delete your own comments
/// (organizers can delete any — RLS enforces). All RLS-scoped to members.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/comment_controller.dart';
import '../../data/comment.dart';
import '../../data/reaction.dart';
import '../widgets/reaction_bar.dart';

class CommentsTab extends ConsumerStatefulWidget {
  const CommentsTab({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<CommentsTab> createState() => _CommentsTabState();
}

class _CommentsTabState extends ConsumerState<CommentsTab> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    final ok = await ref
        .read(commentActionsControllerProvider.notifier)
        .add(widget.eventId, body);
    if (ok) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);
    final commentsAsync = ref.watch(eventCommentsProvider(widget.eventId));
    final reactions =
        ref.watch(eventReactionsProvider(widget.eventId)).value ?? const [];

    ref.listen(commentActionsControllerProvider, (_, n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    });

    return Column(
      children: [
        Expanded(
          child: commentsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(messageForError(e))),
            data: (comments) => comments.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(t.commentsEmpty,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.inkMuted)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: comments.length,
                    itemBuilder: (context, i) {
                      final c = comments[i];
                      return _CommentTile(
                        eventId: widget.eventId,
                        comment: c,
                        myId: myId,
                        reactions: reactions
                            .where((r) => r.commentId == c.id)
                            .toList(),
                      );
                    },
                  ),
          ),
        ),
        const Divider(height: 1),
        // Compose box
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(hintText: t.commentHint),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: _send,
                  tooltip: t.commentSend,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({
    required this.eventId,
    required this.comment,
    required this.myId,
    required this.reactions,
  });
  final String eventId;
  final Comment comment;
  final String? myId;
  final List<Reaction> reactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final isMine = comment.authorId == myId;
    final handle = comment.author.handle ?? '…';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(isMine ? '$handle (${t.youLabel})' : handle,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.violet, fontWeight: FontWeight.w700)),
                ),
                Text(_time(comment.createdAt.toLocal()),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.inkMuted)),
                if (isMine)
                  InkWell(
                    onTap: () => ref
                        .read(commentActionsControllerProvider.notifier)
                        .delete(comment.id),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.close,
                          size: 16, color: AppColors.inkMuted),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(comment.body),
            const SizedBox(height: 8),
            ReactionBar(
              reactions: reactions,
              myUserId: myId,
              onToggle: (emoji) => ref
                  .read(commentActionsControllerProvider.notifier)
                  .toggleReaction(eventId,
                      commentId: comment.id, emoji: emoji),
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
