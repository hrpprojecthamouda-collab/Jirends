/// The "who reacted" sheet — long-press any chip in a [ReactionBar] to see
/// every member who reacted to that target, grouped by emoji.
///
/// Adds no visibility path: an event's reactions are already RLS-scoped to its
/// members, and profiles are world-readable and carry no event data. This just
/// renders names for rows the viewer could already read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/comment_controller.dart';
import '../../data/reaction.dart';
import 'reaction_bar.dart';
import '../../../profile/presentation/user_avatar.dart';

/// Opens the sheet for one reaction target.
Future<void> showReactionUsersSheet(
  BuildContext context, {
  required String eventId,
  String? commentId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _ReactionUsersSheet(eventId: eventId, commentId: commentId),
  );
  // See showEventOverlaySheet: closing a modal restores focus to the page and
  // would otherwise open the keyboard on the comment compose field.
  FocusManager.instance.primaryFocus?.unfocus();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FocusManager.instance.primaryFocus?.unfocus();
  });
}

class _ReactionUsersSheet extends ConsumerWidget {
  const _ReactionUsersSheet({required this.eventId, this.commentId});
  final String eventId;
  final String? commentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final async = ref.watch(
        reactionUsersProvider((eventId: eventId, commentId: commentId)));

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.reactionsTitle.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.inkMuted,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(messageForError(e)),
              ),
              data: (reactions) => reactions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(t.reactionsNone,
                          style: TextStyle(color: AppColors.inkMuted)),
                    )
                  : Flexible(child: _Grouped(reactions: reactions)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reactions grouped by emoji, in the bar's fixed palette order so the sheet
/// reads in the same order as the chips that opened it.
class _Grouped extends StatelessWidget {
  const _Grouped({required this.reactions});
  final List<Reaction> reactions;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // Palette order first, then anything else that somehow exists.
    final emojis = [
      ...kReactionEmojis.where((e) => reactions.any((r) => r.emoji == e)),
      ...reactions.map((r) => r.emoji).toSet().where(
            (e) => !kReactionEmojis.contains(e),
          ),
    ];

    return ListView(
      shrinkWrap: true,
      children: [
        for (final emoji in emojis) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  '${reactions.where((r) => r.emoji == emoji).length}',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
          for (final r in reactions.where((r) => r.emoji == emoji))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: UserAvatar(
                profile: r.user,
                radius: 16,
                background: AppColors.surfaceHi,
                foreground: AppColors.ink,
              ),
              title: Text(r.user?.handle ?? t.reactionsUnknownMember),
            ),
        ],
      ],
    );
  }
}
