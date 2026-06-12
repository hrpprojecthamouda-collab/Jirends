/// A small fixed-set emoji reaction bar. Shows each emoji with its count; the
/// emojis the current user has reacted with are highlighted. Tapping toggles the
/// caller's reaction via [onToggle]. Used for both the event (commentId null)
/// and individual comments.
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
    required this.onToggle,
  });

  /// Reactions relevant to this target (event reactions, or one comment's).
  final List<Reaction> reactions;
  final String? myUserId;
  final void Function(String emoji) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        for (final emoji in kReactionEmojis)
          _Chip(
            emoji: emoji,
            count: reactions.where((r) => r.emoji == emoji).length,
            mine: reactions
                .any((r) => r.emoji == emoji && r.userId == myUserId),
            onTap: () => onToggle(emoji),
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
  });
  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
