/// PollsPreview — the Polls section of the event page: each poll's question,
/// how many people have voted, and whether it's open or closed, without having
/// to open the panel. Tapping anywhere opens the full Polls overlay.
///
/// On the voter count and VIS-7: while a poll is open, each member may read
/// only their OWN vote row — so counting `poll_votes` client-side would report
/// 1 or 0, not the truth. The count here comes from `poll_tallies_for_event`,
/// a member-gated RPC that returns per-option totals and never says who voted.
/// Aggregates are safe; identities are not, and stay hidden until the poll
/// closes. Members may back several options, so votes != voters — the count
/// shown is `voterCount`, distinct people, from its own RPC.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/poll_controller.dart';
import '../../data/poll_repository.dart';

class PollsPreview extends ConsumerWidget {
  const PollsPreview({super.key, required this.eventId, required this.onOpen});

  final String eventId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final pollsAsync = ref.watch(eventPollsProvider(eventId));

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.how_to_vote_outlined,
                    size: 18, color: AppColors.inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(t.detailTabPolls,
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppColors.inkMuted),
              ],
            ),
            // Loading and error stay quiet: the row is still tappable, and a
            // spinner or a red string here would shout louder than a preview
            // deserves. The panel itself reports properly.
            pollsAsync.maybeWhen(
              data: (polls) => polls.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          for (final p in polls) _PollRow(view: p),
                        ],
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PollRow extends StatelessWidget {
  const _PollRow({required this.view});
  final PollView view;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final closed = view.poll.isClosed;
    // Closed reads as settled, open as still live — the same teal/blue pairing
    // the status chips use elsewhere.
    final statusColor = closed ? AppColors.teal : AppColors.blue;

    return Padding(
      // Indented to sit under the section's icon, so the polls read as
      // belonging to the row above rather than as new sections.
      padding: const EdgeInsets.only(left: 28, top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              view.poll.question,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          // Omitted rather than guessed when the count is unavailable.
          if (view.voterCount != null) ...[
            const SizedBox(width: 8),
            Text(
              t.pollVoters(view.voterCount!),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.inkMuted),
            ),
          ],
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: statusColor.withOpacity(0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              closed ? t.pollClosed : t.pollOpen,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
