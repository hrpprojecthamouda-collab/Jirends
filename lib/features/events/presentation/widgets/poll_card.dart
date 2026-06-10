/// PollCard — renders one poll (a PollView). Open: options with tally bars, tap
/// to (re)cast your vote; the creator gets a Close button. Closed: the winner
/// (or tie), a wheel animation for weighted_random, and the who-voted-what
/// breakdown. Voting/closing errors are surfaced by the parent tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/poll_controller.dart';
import '../../data/poll.dart';
import '../../data/poll_repository.dart';
import 'poll_wheel.dart';

class PollCard extends ConsumerWidget {
  const PollCard({super.key, required this.view});
  final PollView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);
    final poll = view.poll;
    final isCreator = poll.createdBy == myId;
    final actions = ref.read(pollActionsControllerProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: question + chips.
            Text(poll.question,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _chip(context, _kindLabel(t, poll.kind), AppColors.blue),
              _chip(
                  context,
                  poll.mode == PollMode.weightedRandom
                      ? t.pollModeWheel
                      : t.pollModeMajority,
                  AppColors.violet),
              _chip(context, poll.isOpen ? t.pollOpen : t.pollClosed,
                  poll.isOpen ? AppColors.teal : AppColors.inkMuted),
            ]),
            const SizedBox(height: 12),

            // Options with tally bars.
            for (final o in view.options)
              _OptionRow(
                label: o.label,
                votes: view.votesFor(o.id),
                total: view.totalVotes,
                selected: view.myOptionId == o.id,
                isWinner: poll.winningOptionId == o.id,
                canVote: poll.isOpen,
                onTap: poll.isOpen
                    ? () => actions.vote(poll.id, poll.eventId, o.id)
                    : null,
              ),

            const SizedBox(height: 8),

            // Closed-state outcome.
            if (poll.isClosed) _outcome(context, t),

            // Wheel animation for a closed weighted_random poll with a winner.
            if (poll.isClosed &&
                poll.mode == PollMode.weightedRandom &&
                poll.winningOptionId != null &&
                view.totalVotes > 0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: PollWheel(
                    labels: [for (final o in view.options) o.label],
                    weights: [for (final o in view.options) view.votesFor(o.id)],
                    winnerIndex: view.options
                        .indexWhere((o) => o.id == poll.winningOptionId),
                  ),
                ),
              ),

            // Creator controls.
            if (isCreator) ...[
              const Divider(height: 20, color: AppColors.outline),
              Row(
                children: [
                  if (poll.isOpen)
                    FilledButton.icon(
                      onPressed: () => actions.close(poll.id, poll.eventId),
                      icon: const Icon(Icons.how_to_vote, size: 18),
                      label: Text(t.pollClose),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => actions.reopen(poll.id, poll.eventId),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(t.pollReopen),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: t.pollDelete,
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.inkMuted),
                    onPressed: () => actions.delete(poll.id, poll.eventId),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _outcome(BuildContext context, AppLocalizations t) {
    final poll = view.poll;
    final String text;
    Color color = AppColors.teal;
    if (poll.isTie) {
      text = t.pollTie;
      color = AppColors.yellow;
    } else if (poll.winningOptionId == null) {
      text = t.pollNoVotes;
      color = AppColors.inkMuted;
    } else {
      final label = view.options
          .firstWhere((o) => o.id == poll.winningOptionId,
              orElse: () => view.options.first)
          .label;
      text = t.pollWinner(label);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }

  String _kindLabel(AppLocalizations t, PollKind k) => switch (k) {
        PollKind.general => t.pollKindGeneral,
        PollKind.date => t.pollKindDate,
        PollKind.place => t.pollKindPlace,
      };

  Widget _chip(BuildContext context, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          color: color.withOpacity(0.16),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      );
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.votes,
    required this.total,
    required this.selected,
    required this.isWinner,
    required this.canVote,
    required this.onTap,
  });
  final String label;
  final int votes;
  final int total;
  final bool selected;
  final bool isWinner;
  final bool canVote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final frac = total == 0 ? 0.0 : votes / total;
    final accent = isWinner
        ? AppColors.teal
        : (selected ? AppColors.violet : AppColors.inkMuted);

    final clamped = frac.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? AppColors.violet : AppColors.outline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                // Tally bar fill — sized to a fraction of the measured width,
                // matched to the content height by the Positioned.fill wrapper.
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: c.maxWidth * clamped,
                        // ignore: deprecated_member_use
                        color: accent.withOpacity(0.18),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      if (selected)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.check_circle,
                              size: 16, color: AppColors.violet),
                        ),
                      Expanded(child: Text(label)),
                      Text(t.pollVotes(votes),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppColors.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
