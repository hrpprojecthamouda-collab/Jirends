/// A small fixed-set emoji reaction bar. Shows each emoji with its count.
///
/// A user holds at most ONE reaction per target: tapping an emoji selects it
/// (replacing whatever they had), tapping the one they're already on clears it.
/// Only that one chip is highlighted. Long-pressing any chip opens the "who
/// reacted" sheet. Used for both the event (commentId null) and comments.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/reaction.dart';

/// The fixed reaction palette for v1.
const kReactionEmojis = ['👍', '🎉', '❤️', '😂'];

class ReactionBar extends StatelessWidget {
  const ReactionBar({
    super.key,
    required this.reactions,
    required this.myUserId,
    required this.onSelect,
    this.onShowUsers,
  });

  /// Reactions relevant to this target (event reactions, or one comment's).
  final List<Reaction> reactions;
  final String? myUserId;

  /// Tapped [emoji] becomes the caller's only reaction — or is cleared, if it
  /// already was.
  final void Function(String emoji) onSelect;

  /// Long-press on any chip. Null disables the gesture.
  final VoidCallback? onShowUsers;

  /// The caller's current emoji on this target, if any. Defensive `firstOrNull`
  /// rather than `single`: rows predating the one-reaction-per-user rule may
  /// still have a user on several emojis until they next tap (see
  /// ReactionRepository.setMyReaction).
  String? get _myEmoji =>
      reactions.where((r) => r.userId == myUserId).map((r) => r.emoji).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final mine = _myEmoji;
    return Wrap(
      spacing: 6,
      children: [
        for (final emoji in kReactionEmojis)
          _Chip(
            emoji: emoji,
            count: reactions.where((r) => r.emoji == emoji).length,
            mine: mine == emoji,
            onTap: () => onSelect(emoji),
            onLongPress: onShowUsers,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.emoji,
    required this.count,
    required this.mine,
    required this.onTap,
    this.onLongPress,
  });
  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: mine ? AppColors.surfaceHi : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: mine ? AppColors.primary : AppColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text('$count',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: mine ? AppColors.ink : AppColors.inkMuted)),
            ],
          ],
        ),
      ),
    );
  }
}
