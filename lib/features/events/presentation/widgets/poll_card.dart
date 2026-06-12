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
  const PollCard({
    super.key,
    required this.view,
    this.isEventOrganizer = false,
  });
  final PollView view;

  /// Whether the current user is an organizer of the event. An organizer may
  /// delete ANY poll (not just their own) — but only the poll's creator may
  /// close/reopen it.
  final bool isEventOrganizer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);
    final poll = view.poll;
    final isCreator = poll.createdBy == myId;
    final canDelete = isCreator || isEventOrganizer;
    final actions = ref.read(pollActionsControllerProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: question + chips. Special kinds (day/time/place) render
            // the viewer-localized auto-title, not the stored question.
            Text(_title(t, poll),
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
            // Special kinds: the winner is written onto the event at close.
            if (poll.kind != PollKind.general) ...[
              const SizedBox(height: 6),
              Text(t.pollAppliedToEvent,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.inkMuted)),
            ],
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

            // Controls. The poll's CREATOR can close/reopen it; the event
            // ORGANIZER (even if not the poll's creator) can delete it. The DB
            // (polls_delete_creator: created_by = uid OR is_event_organizer)
            // enforces the same.
            //
            // We deliberately AVOID Material buttons here: their internal
            // _RenderInputPadding (min tap-target) throws "BoxConstraints forces
            // an infinite width" when the card is measured for intrinsic width.
            // Plain tappable chips have no _RenderInputPadding and size cleanly.
            if (canDelete) ...[
              const Divider(height: 20, color: AppColors.outline),
              Row(
                mainAxisAlignment: isCreator
                    ? MainAxisAlignment.spaceBetween
                    : MainAxisAlignment.end,
                children: [
                  if (isCreator)
                    if (poll.isOpen)
                      _ActionChip(
                        icon: Icons.how_to_vote,
                        label: t.pollClose,
                        color: AppColors.primary,
                        filled: true,
                        onTap: () => actions.close(poll.id, poll.eventId),
                      )
                    else
                      _ActionChip(
                        icon: Icons.refresh,
                        label: t.pollReopen,
                        color: AppColors.primary,
                        filled: false,
                        onTap: () => actions.reopen(poll.id, poll.eventId),
                      ),
                  _ActionChip(
                    icon: Icons.delete_outline,
                    label: t.pollDelete,
                    color: AppColors.coral,
                    filled: false,
                    iconOnly: true,
                    onTap: () => _confirmDelete(context, t, actions),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Confirm before deleting — organizers can delete OTHER people's polls, so
  /// a stray tap must not silently destroy someone's poll and its votes.
  Future<void> _confirmDelete(BuildContext context, AppLocalizations t,
      PollActionsController actions) async {
    final poll = view.poll;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(t.pollDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.pollDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) await actions.delete(poll.id, poll.eventId);
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
        PollKind.time => t.pollKindTime,
        PollKind.place => t.pollKindPlace,
      };

  /// Special kinds show a fixed, viewer-localized title; general polls show
  /// their stored question.
  String _title(AppLocalizations t, Poll poll) => switch (poll.kind) {
        PollKind.general => poll.question,
        PollKind.date => t.pollTitleDay,
        PollKind.time => t.pollTitleTime,
        PollKind.place => t.pollTitlePlace,
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

/// A small tappable chip used for the creator's poll actions. Plain
/// InkWell+Container (no Material button), so it carries no _RenderInputPadding
/// and lays out cleanly even under an intrinsic-width measurement.
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
    this.iconOnly = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final bool iconOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 8 : 12, vertical: 8),
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          color: filled ? color.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            if (!iconOnly) ...[
              const SizedBox(width: 6),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: color, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
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
        : (selected ? AppColors.primary : AppColors.inkMuted);

    final clamped = frac.clamp(0.0, 1.0);
    // No Stack/Positioned/LayoutBuilder: a Column whose children stretch to the
    // parent's (bounded) width, with a LinearProgressIndicator as the tally bar.
    // This can never force an infinite width inside a ListView.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.check_circle,
                          size: 16, color: AppColors.primary),
                    ),
                  Expanded(child: Text(label)),
                  Text(t.pollVotes(votes),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.inkMuted)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: clamped,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceHi,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
