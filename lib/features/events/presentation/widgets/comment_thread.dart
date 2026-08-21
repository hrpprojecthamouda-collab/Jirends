/// CommentThread — the list of an event's top-level comments, embedded
/// directly in the Overview tab (below Description) rather than living on its
/// own tab. Deliberately NOT scrollable on its own: it renders its tiles as
/// plain children so the caller's single outer scrollable owns all scrolling
/// (avoids nested-scrollable jank). Composing lives separately in
/// [CommentComposeBubble]. All RLS-scoped to members.
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
import 'reaction_bar.dart';
import 'reaction_users_sheet.dart';
import 'thread_title_dialog.dart';

class CommentThread extends ConsumerWidget {
  const CommentThread({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);
    final commentsAsync = ref.watch(eventCommentsProvider(eventId));
    final reactions =
        ref.watch(eventReactionsProvider(eventId)).value ?? const [];

    ref.listen(commentActionsControllerProvider, (_, n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    });

    return commentsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(messageForError(e))),
      ),
      data: (comments) => comments.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                t.commentsEmpty,
                style: TextStyle(color: AppColors.inkMuted),
              ),
            )
          : Column(
              children: [
                for (final (i, root) in comments.indexed) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.outline),
                  _CommentTile(
                    eventId: eventId,
                    root: root,
                    myId: myId,
                    reactions: reactions
                        .where((r) => r.commentId == root.comment.id)
                        .toList(),
                  ),
                ],
              ],
            ),
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

    // No Card here: the whole Comments section is already one card (see
    // _Block in overview_tab.dart), and nesting a card inside it reads as
    // noise. Rows are separated by hairlines instead.
    return InkWell(
      onTap: () => context.push(
        AppRoutes.discussion(eventId, comment.id),
        extra: comment,
      ),
      onLongPress: () => _renameDiscussion(context, ref),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isMine ? '$handle (${t.youLabel})' : handle,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  formatShortTime(comment.createdAt.toLocal()),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.inkMuted),
                ),
                if (isMine)
                  InkWell(
                    onTap: () => _confirmDelete(context, ref),
                    child: Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.inkMuted,
                      ),
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
              onSelect: (emoji) => ref
                  .read(commentActionsControllerProvider.notifier)
                  .setMyReaction(eventId, commentId: comment.id, emoji: emoji),
              onShowUsers: () => showReactionUsersSheet(
                context,
                eventId: eventId,
                commentId: comment.id,
              ),
            ),
            // Discussion footer: title + reply count (once a discussion exists).
            if (root.hasDiscussion) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 14,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      comment.threadTitle?.isNotEmpty == true
                          ? comment.threadTitle!
                          : t.discussionTitleDefault,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t.discussionReplies(root.replyCount),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppColors.inkMuted),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.inkMuted,
                  ),
                ],
              ),
            ],
          ],
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
