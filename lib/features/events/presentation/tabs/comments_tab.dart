/// Comments tab — the event's thread plus a compose box. Each comment shows its
/// author, body, time, and a reaction bar. You can delete your own comments
/// (organizers can delete any — RLS enforces). All RLS-scoped to members.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/util/short_time.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/comment_controller.dart';
import '../../data/comment_repository.dart';
import '../../data/reaction.dart';
import '../widgets/reaction_bar.dart';
import '../widgets/thread_title_dialog.dart';

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
                      final root = comments[i];
                      return _CommentTile(
                        eventId: widget.eventId,
                        root: root,
                        myId: myId,
                        reactions: reactions
                            .where((r) => r.commentId == root.comment.id)
                            .toList(),
                      );
                    },
                  ),
          ),
        ),
        const Divider(height: 1),
        // Compose box — pinned to the bottom and lifted above the keyboard when
        // it opens (the tall ticket app bar otherwise pushes it off-screen).
        Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 8,
            top: 8,
            bottom: 8 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
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

/// A top-level comment. TAP opens its discussion; LONG-PRESS names/renames it
/// (any member). The footer (title + reply count) appears once a discussion
/// exists (≥1 reply or a title).
class _CommentTile extends ConsumerWidget {
  const _CommentTile({
    required this.eventId,
    required this.root,
    required this.myId,
    required this.reactions,
  });
  final String eventId;
  final RootComment root;
  final String? myId;
  final List<Reaction> reactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final comment = root.comment;
    final isMine = comment.authorId == myId;
    final handle = comment.author.handle ?? '…';

    return Card(
      child: InkWell(
        onTap: () => context.push(
            AppRoutes.discussion(eventId, comment.id),
            extra: comment),
        onLongPress: () => _renameDiscussion(context, ref),
        borderRadius: BorderRadius.circular(16),
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
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
                  ),
                  Text(formatShortTime(comment.createdAt.toLocal()),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.inkMuted)),
                  if (isMine)
                    InkWell(
                      onTap: () => _confirmDelete(context, ref),
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
                    .toggleReaction(eventId, commentId: comment.id, emoji: emoji),
              ),
              // Discussion footer: title + reply count (once a discussion exists).
              if (root.hasDiscussion) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.forum_outlined,
                        size: 14, color: AppColors.blue),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        comment.threadTitle?.isNotEmpty == true
                            ? comment.threadTitle!
                            : t.discussionTitleDefault,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.blue, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(t.discussionReplies(root.replyCount),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: AppColors.inkMuted)),
                    const Icon(Icons.chevron_right,
                        size: 16, color: AppColors.inkMuted),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameDiscussion(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(commentActionsControllerProvider.notifier);
    final rootId = root.comment.id;
    final current = root.comment.threadTitle ?? '';
    final title = await showDialog<String>(
      context: context,
      builder: (_) => ThreadTitleDialog(initial: current),
    );
    if (title == null) return; // cancelled
    await notifier.setThreadTitle(rootId, title.isEmpty ? null : title);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final notifier = ref.read(commentActionsControllerProvider.notifier);
    final id = root.comment.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(t.commentDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.commentDelete),
          ),
        ],
      ),
    );
    if (ok == true) await notifier.delete(id);
  }
}
