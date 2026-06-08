/// Overview tab — description and when/where. Organizers can tap any field
/// (description, location, dates) to edit it inline (tick to confirm, cross to
/// cancel). The status lives in the app bar (top-right chip), not here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/event_detail_controller.dart';
import '../../application/event_list_controller.dart';
import '../../data/event.dart';
import '../event_detail_screen.dart';
import '../widgets/inline_editable_text.dart';

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key, required this.event});
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);
    final members = ref.watch(eventMembersProvider(event.id)).value ?? const [];
    final isOrganizer = isCurrentUserOrganizer(members, myId);

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
      ],
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtDateTime(DateTime d) =>
    '${_fmtDate(d)}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// The "When" row. For a TRIP it shows a date range and edits start+end days;
/// for any other type it shows a single date+time and edits that (ends_at stays
/// null). Organizer-only editing; saves via the edit controller.
class _DatesRow extends ConsumerWidget {
  const _DatesRow({required this.event, required this.canEdit});
  final Event event;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = event.startsAt?.toLocal();
    final e = event.endsAt?.toLocal();
    final String text;
    if (s == null) {
      text = t.detailWhen;
    } else if (event.isTrip) {
      text = e == null ? _fmtDate(s) : '${_fmtDate(s)} → ${_fmtDate(e)}';
    } else {
      text = _fmtDateTime(s);
    }
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
      onTap: () => event.isTrip ? _editRange(context, ref) : _editSingle(context, ref),
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row),
    );
  }

  // Trip: start + end days, no time.
  Future<void> _editRange(BuildContext context, WidgetRef ref) async {
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
    await ref.read(editEventControllerProvider.notifier).save(
          event.id,
          startsAt: start,
          endsAt: end,
          clearEndsAt: end == null,
        );
  }

  // Non-trip: single date + time -> starts_at; ends_at always cleared.
  Future<void> _editSingle(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: event.startsAt?.toLocal() ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(event.startsAt?.toLocal() ?? now),
    );
    final dt = DateTime(
        day.year, day.month, day.day, time?.hour ?? 0, time?.minute ?? 0);
    await ref.read(editEventControllerProvider.notifier).save(
          event.id,
          startsAt: dt,
          clearEndsAt: true,
        );
  }
}

