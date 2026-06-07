/// Overview tab — description, when/where, the status workflow, and event-level
/// reactions. Organizers can tap any field (description, location, dates) to
/// edit it inline (tick to confirm, cross to cancel); the workflow is built from
/// event_type_phases (never hardcoded) — organizers tap a phase to advance,
/// others see read-only chips.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/comment_controller.dart';
import '../../application/event_detail_controller.dart';
import '../../application/event_list_controller.dart';
import '../../application/event_status_controller.dart';
import '../../data/event.dart';
import '../event_detail_screen.dart';
import '../widgets/inline_editable_text.dart';
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

    void onActionError(_, AsyncValue n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    }

    ref.listen(eventStatusControllerProvider, onActionError);
    ref.listen(editEventControllerProvider, onActionError);

    final edit = ref.read(editEventControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Description — tap to edit (organizers).
        InlineEditableText(
          value: event.description ?? '',
          placeholder: t.detailNoDescription,
          canEdit: isOrganizer,
          multiline: true,
          maxLength: 2000,
          onSubmit: (v) => edit.save(
            event.id,
            description: v.isEmpty ? null : v,
            clearDescription: v.isEmpty,
          ),
        ),
        const SizedBox(height: 20),

        // When (tap to edit dates) / Where (tap to edit location).
        _DatesRow(event: event, canEdit: isOrganizer),
        const SizedBox(height: 4),
        InlineEditableText(
          value: event.location ?? '',
          placeholder: t.detailWhere,
          canEdit: isOrganizer,
          leading: Icons.place_outlined,
          onSubmit: (v) => edit.save(
            event.id,
            location: v.isEmpty ? null : v,
            clearLocation: v.isEmpty,
          ),
        ),
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
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// The "When" row. Display shows the date range (or a prompt). For organizers,
/// tapping opens start/end date pickers and saves via the edit controller.
class _DatesRow extends ConsumerWidget {
  const _DatesRow({required this.event, required this.canEdit});
  final Event event;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = event.startsAt?.toLocal();
    final e = event.endsAt?.toLocal();
    final text = s == null
        ? t.detailWhen
        : (e == null ? _fmtDate(s) : '${_fmtDate(s)} → ${_fmtDate(e)}');
    final hasValue = s != null;

    final row = Row(
      children: [
        const Icon(Icons.event_outlined, size: 18, color: AppColors.inkMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: hasValue ? AppColors.ink : AppColors.inkMuted)),
        ),
        if (canEdit)
          const Icon(Icons.edit_outlined, size: 16, color: AppColors.inkMuted),
      ],
    );

    if (!canEdit) return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row);
    return InkWell(
      onTap: () => _editDates(context, ref),
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row),
    );
  }

  Future<void> _editDates(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final start = await showDatePicker(
      context: context,
      initialDate: event.startsAt?.toLocal() ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      helpText: AppLocalizations.of(context).createFieldStarts,
    );
    if (start == null || !context.mounted) return;
    final end = await showDatePicker(
      context: context,
      initialDate: event.endsAt?.toLocal() ?? start,
      firstDate: start,
      lastDate: DateTime(now.year + 5),
      helpText: AppLocalizations.of(context).createFieldEnds,
    );
    // end may be null (single-day); that's fine.
    await ref.read(editEventControllerProvider.notifier).save(
          event.id,
          startsAt: start,
          endsAt: end,
          clearEndsAt: end == null,
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
