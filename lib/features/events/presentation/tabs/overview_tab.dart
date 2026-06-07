/// Overview tab — description, when/where, the status workflow, and event-level
/// reactions. The workflow is built from event_type_phases (never hardcoded);
/// organizers can tap a phase to advance, others see read-only chips.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/comment_controller.dart';
import '../../application/event_detail_controller.dart';
import '../../application/event_status_controller.dart';
import '../../data/event.dart';
import '../event_detail_screen.dart';
import '../widgets/reaction_bar.dart';

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key, required this.event});
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);
    final members = ref.watch(eventMembersProvider(event.id)).value ?? const [];
    final isOrganizer = isCurrentUserOrganizer(members, myId);
    final phases = ref.watch(eventPhasesProvider(event.eventType));
    final reactions = ref.watch(eventReactionsProvider(event.id)).value ?? const [];

    ref.listen(eventStatusControllerProvider, (_, n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    });

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Description
        Text(
          (event.description?.isNotEmpty ?? false)
              ? event.description!
              : t.detailNoDescription,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: (event.description?.isNotEmpty ?? false)
                  ? AppColors.ink
                  : AppColors.inkMuted),
        ),
        const SizedBox(height: 20),

        // When / Where
        if (event.startsAt != null)
          _InfoRow(
              icon: Icons.event_outlined,
              label: t.detailWhen,
              value: _formatRange(event)),
        if (event.location != null && event.location!.isNotEmpty)
          _InfoRow(
              icon: Icons.place_outlined,
              label: t.detailWhere,
              value: event.location!),
        const SizedBox(height: 20),

        // Status workflow
        Text(t.detailStatus,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        phases.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(messageForError(e),
              style: const TextStyle(color: AppColors.coral)),
          data: (list) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in list)
                _PhaseChip(
                  label: p.label,
                  selected: event.status == p.key,
                  color: AppColors.forPhaseKey(p.key),
                  onTap: isOrganizer && event.status != p.key
                      ? () => ref
                          .read(eventStatusControllerProvider.notifier)
                          .advance(event.id, p.key)
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Event reactions
        ReactionBar(
          reactions: reactions.where((r) => r.isOnEvent).toList(),
          myUserId: myId,
          onToggle: (emoji) => ref
              .read(commentActionsControllerProvider.notifier)
              .toggleReaction(event.id, emoji: emoji),
        ),
      ],
    );
  }

  String _formatRange(Event event) {
    final s = event.startsAt!.toLocal();
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final e = event.endsAt?.toLocal();
    return e == null ? fmt(s) : '${fmt(s)} → ${fmt(e)}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.inkMuted)),
                Text(value, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          color: selected ? color.withOpacity(0.22) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : AppColors.outline,
              width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? color : AppColors.inkMuted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
      ),
    );
  }
}
