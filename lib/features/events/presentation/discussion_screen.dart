/// DiscussionScreen — the thread of replies hanging off one top-level comment.
/// Shows the root comment, the (live) replies with per-reply reactions, a
/// compose bar to add a reply, and a renamable title (any member). All
/// RLS-scoped to event members; replies are plain comments with parent_id set.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/short_time.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/comment_controller.dart';
import '../data/comment.dart';
import '../data/reaction.dart';
import 'widgets/reaction_bar.dart';
import 'widgets/reaction_users_sheet.dart';
import 'widgets/thread_title_dialog.dart';

class DiscussionScreen extends ConsumerStatefulWidget {
  const DiscussionScreen({
    super.key,
    required this.eventId,
    required this.rootId,
    this.rootComment,
  });
  final String eventId;
  final String rootId;

  /// Optionally passed via go_router `extra` to avoid a re-fetch.
  final Comment? rootComment;

  @override
  ConsumerState<DiscussionScreen> createState() => _DiscussionScreenState();
}

class _DiscussionScreenState extends ConsumerState<DiscussionScreen> {
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
        .reply(widget.eventId, widget.rootId, body);
    if (ok) _input.clear();
  }

  Future<void> _rename(Comment root) async {
    final notifier = ref.read(commentActionsControllerProvider.notifier);
    final title = await showDialog<String>(
      context: context,
      builder: (_) => ThreadTitleDialog(initial: root.threadTitle ?? ''),
    );
    if (title == null) return;
    await notifier.setThreadTitle(widget.rootId, title.isEmpty ? null : title);
    // Refresh the header if we're showing the passed-in copy.
    ref.invalidate(commentByIdProvider(widget.rootId));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);

    // Prefer the passed-in root; otherwise fetch it (and pick up title edits).
    final fetchedRoot = ref.watch(commentByIdProvider(widget.rootId));
    final root = fetchedRoot.value ?? widget.rootComment;

    final repliesAsync = ref.watch(repliesProvider(widget.rootId));
    final reactions =
        ref.watch(eventReactionsProvider(widget.eventId)).value ?? const [];

    ref.listen(commentActionsControllerProvider, (_, n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    });

    final title = (root?.threadTitle?.isNotEmpty ?? false)
        ? root!.threadTitle!
        : t.discussionTitleDefault;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: root == null ? null : () => _rename(root),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, size: 16),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // The root comment that started the discussion.
          if (root != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _MessageCard(
                comment: root,
                myId: myId,
                accent: AppColors.primary,
                reactions:
                    reactions.where((r) => r.commentId == root.id).toList(),
                eventId: widget.eventId,
                isRoot: true,
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Divider(),
          ),
          Expanded(
            child: repliesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(messageForError(e))),
              data: (replies) => replies.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(t.discussionEmpty,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.inkMuted)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: replies.length,
                      itemBuilder: (context, i) {
                        final c = replies[i];
                        return _MessageCard(
                          comment: c,
                          myId: myId,
                          accent: AppColors.blue,
                          reactions: reactions
                              .where((r) => r.commentId == c.id)
                              .toList(),
                          eventId: widget.eventId,
                          isRoot: false,
                        );
                      },
                    ),
            ),
          ),
          const Divider(height: 1),
          // Reply compose bar — lifted above the keyboard.
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
                      decoration:
                          InputDecoration(hintText: t.discussionReplyHint),
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
      ),
    );
  }
}

/// One message in the discussion (the root or a reply). You can delete your own
/// (organizers can delete any — RLS enforces).
class _MessageCard extends ConsumerWidget {
  const _MessageCard({
    required this.comment,
    required this.myId,
    required this.accent,
    required this.reactions,
    required this.eventId,
    required this.isRoot,
  });
  final Comment comment;
  final String? myId;
  final Color accent;
  final List<Reaction> reactions;
  final String eventId;
  final bool isRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final isMine = comment.authorId == myId;
    final handle = comment.author.handle ?? '…';

    return Card(
      margin: EdgeInsets.only(bottom: isRoot ? 4 : 8),
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
                          color: accent, fontWeight: FontWeight.w700)),
                ),
                Text(formatShortTime(comment.createdAt.toLocal()),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.inkMuted)),
                if (isMine)
                  InkWell(
                    onTap: () => _confirmDelete(context, ref),
                    child: Padding(
                      padding: EdgeInsets.only(left: 8),
                      child:
                          Icon(Icons.close, size: 16, color: AppColors.inkMuted),
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
          ],
        ),
      ),
    );
  }

  /// Confirm, then delete. Deleting the ROOT cascades its replies and closes
  /// the discussion screen (otherwise the user is stranded on a dead thread).
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final notifier = ref.read(commentActionsControllerProvider.notifier);
    final confirmed = await showDialog<bool>(
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
    if (confirmed != true) return;
    final ok = await notifier.delete(comment.id);
    if (ok && isRoot && context.mounted) Navigator.of(context).pop();
  }
}
