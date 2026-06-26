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
    final myConflicts = ref.watch(myConflictsProvider(event.id)).value ?? const [];

    final edit = ref.read(editEventControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // Self-conflict banner: safe to name the other event here — the
        // viewer is, by definition, a member of both (see myConflictsProvider).
        if (myConflicts.isNotEmpty)
          _ConflictBanner(
            text: t.eventConflictBanner(
              myConflicts.length,
              myConflicts.map((c) => c.title).join(', '),
            ),
          ),
        // Description block — bigger. Soft separation only (label + hairline).
        _Block(
          label: t.detailDescription,
          minHeight: 140,
          child: InlineEditableText(
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
        ),
        // Date block.
        _Block(
          label: t.detailWhen,
          child: _DatesRow(event: event, canEdit: isOrganizer),
        ),
        // Place block (last one: no trailing divider).
        _Block(
          label: t.detailWhere,
          divider: false,
          child: InlineEditableText(
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
        ),
      ],
    );
  }
}

/// A dismissible-for-this-session warning banner shown to a member who has a
/// time conflict between THIS event and another one they're also in. Safe to
/// name the other event: the viewer is necessarily a member of both.
class _ConflictBanner extends StatefulWidget {
  const _ConflictBanner({required this.text});
  final String text;

  @override
  State<_ConflictBanner> createState() => _ConflictBannerState();
}

class _ConflictBannerState extends State<_ConflictBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          color: AppColors.coral.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.coral),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_outlined,
                size: 18, color: AppColors.coral),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(widget.text,
                    style: const TextStyle(color: AppColors.coral)),
              ),
            ),
            InkWell(
              onTap: () => setState(() => _dismissed = true),
              borderRadius: BorderRadius.circular(16),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: AppColors.coral),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A soft "block" of overview data: a small muted label above the content, with
/// generous spacing and a hairline divider below (unless [divider] is false).
/// Not a card — just a visual grouping/separation. [minHeight] lets the
/// description block be visibly taller.
class _Block extends StatelessWidget {
  const _Block({
    required this.label,
    required this.child,
    this.minHeight = 0,
    this.divider = true,
  });
  final String label;
  final Widget child;
  final double minHeight;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.inkMuted,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
        const SizedBox(height: 18),
        if (divider) const Divider(height: 1, color: AppColors.outline),
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

