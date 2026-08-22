/// Overview — the event's single scrollable page, now that the TabBar is gone.
/// In order: when, where, description, host + attendees, polls, comments,
/// files. Organizers can tap any field (description, location, dates) to edit
/// it inline (tick to confirm, cross to cancel). The status lives in the app
/// bar (top-right chip), not here.
///
/// What used to be a tab is now either inline (comments, files), a row that
/// opens an overlay panel (polls, and the roster via the attendees strip), or
/// a toolbox entry in the app bar (expenses, history). The comment compose bar
/// ([CommentComposeBubble]) sits inline under the thread — idle it's 50%
/// opacity so it doesn't compete with the content, and comes to full opacity
/// once tapped or holding a draft.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/util/weekday.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/event_detail_controller.dart';
import '../../application/event_list_controller.dart';
import '../../data/event.dart';
import '../event_detail_screen.dart';
import '../widgets/comment_compose_bubble.dart';
import '../widgets/comment_thread.dart';
import '../widgets/description_editor_sheet.dart';
import '../widgets/event_overlay_sheet.dart';
import '../widgets/host_attendees_row.dart';
import '../widgets/inline_editable_text.dart';
import '../widgets/polls_preview.dart';
import 'files_tab.dart';
import 'polls_tab.dart';

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key, required this.event});
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);
    final members = ref.watch(eventMembersProvider(event.id)).value ?? const [];
    final isOrganizer = isCurrentUserOrganizer(members, myId);
    final myConflicts =
        ref.watch(myConflictsProvider(event.id)).value ?? const [];

    final edit = ref.read(editEventControllerProvider.notifier);

    // The compose bubble scrolls WITH the page, sitting directly under the
    // comment thread. It used to float over everything via a Stack, which was
    // fine while Comments was the last section — but now Polls sits above it
    // and Files below, and a floating bar silently swallowed taps meant for
    // those rows. Inline keeps it adjacent to what it composes and unable to
    // cover anything.
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
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
          // Date block. No label: the calendar icon already says "when".
          _Block(
            child: _DatesRow(event: event, canEdit: isOrganizer),
          ),
          // Place block. No label: the pin icon already says "where".
          _Block(
            child: InlineEditableText(
              value: event.location ?? '',
              placeholder: t.detailWhere,
              canEdit: isOrganizer,
              leading: Icons.place_outlined,
              // Matches the date row above it — both are facts about the
              // event, ranked below the description.
              style: Theme.of(context).textTheme.bodyMedium,
              onSubmit: (v) => edit.save(
                event.id,
                location: v.isEmpty ? null : v,
                clearLocation: v.isEmpty,
              ),
            ),
          ),
          // Description. No reserved min-height any more: the card gives it
          // presence on its own, so a one-word description no longer sits in a
          // tall empty box. Unlike the date and the location, editing it opens
          // a full-height sheet — it's a paragraph, not a value.
          _Block(
            label: t.detailDescription,
            child: InlineEditableText(
              value: event.description ?? '',
              placeholder: t.detailNoDescription,
              canEdit: isOrganizer,
              multiline: true,
              maxLength: 2000,
              onEditTap: () => _editDescription(context, event, edit),
              onSubmit: (v) => edit.save(
                event.id,
                description: v.isEmpty ? null : v,
                clearDescription: v.isEmpty,
              ),
            ),
          ),
          // Host + attendees, straight after the description. Tapping
          // either side opens the roster/RSVP panel.
          _Block(child: HostAttendeesRow(event: event)),
          // Polls — previews each poll (question, voters, open/closed) and
          // opens the full panel on tap.
          _Block(
            child: PollsPreview(
              eventId: event.id,
              onOpen: () => showEventOverlaySheet(
                context,
                title: t.detailTabPolls,
                child: PollsTab(eventId: event.id),
              ),
            ),
          ),
          // Comment thread + its compose bar, together.
          _Block(
            label: t.detailTabComments,
            child: Column(
              children: [
                CommentThread(eventId: event.id),
                const SizedBox(height: 10),
                CommentComposeBubble(eventId: event.id),
              ],
            ),
          ),
          // Files last, per the layout spec.
          _Block(
            label: t.detailTabFiles,
            child: FilesTab(eventId: event.id, shrinkWrap: true),
          ),
        ],
      ),
    );
  }
}

/// Open the full-height description editor and persist whatever comes back.
/// A null result means the user backed out, which is not the same as clearing
/// the description — only an empty string saved on purpose does that.
Future<void> _editDescription(
  BuildContext context,
  Event event,
  EditEventController edit,
) async {
  final text = await showDescriptionEditor(
    context,
    initial: event.description ?? '',
    maxLength: 2000,
  );
  if (text == null) return;
  await edit.save(
    event.id,
    description: text.isEmpty ? null : text,
    clearDescription: text.isEmpty,
  );
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
            Icon(
              Icons.warning_amber_outlined,
              size: 18,
              color: AppColors.coral,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  widget.text,
                  style: TextStyle(color: AppColors.coral),
                ),
              ),
            ),
            InkWell(
              onTap: () => setState(() => _dismissed = true),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
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

/// One section of the event page, rendered as its own card: an optional small
/// muted label above the content, on an [AppColors.surface] panel separated
/// from its neighbours by margin rather than a hairline.
///
/// The styling is deliberately LOCAL rather than the global `cardTheme`: that
/// theme is shared by list items across ~16 other screens (friends, groups,
/// home feed, the events list…), and restyling sections here must not drag
/// those along.
///
/// Sections whose children were themselves cards (comments, files) render them
/// flat inside this one — a card inside a card reads as visual noise.
/// [label] can be omitted when the content already carries its own affordance
/// (e.g. a leading icon).
class _Block extends StatelessWidget {
  const _Block({this.label, required this.child});
  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(
              label!.toUpperCase(),
              // ExtraBold on full ink, not muted grey. At caption size these
              // were the weakest thing on the page — small, light AND low
              // contrast — so the sections they name did not read as sections
              // at all. Weight alone was not enough; the colour was doing as
              // much of the damage as the size.
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.ink,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Align(alignment: Alignment.topLeft, child: child),
        ],
      ),
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Date prefixed with its weekday, e.g. "Sat 30/08/2026" — saves the reader
/// working out which day of the week that is.
String _fmtDay(AppLocalizations t, DateTime d) =>
    '${weekdayShort(t, d)} ${_fmtDate(d)}';

String _fmtDateTime(AppLocalizations t, DateTime d) =>
    '${_fmtDay(t, d)}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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
      text = e == null
          ? _fmtDay(t, s)
          : '${_fmtDay(t, s)} → ${_fmtDay(t, e)}';
    } else {
      text = _fmtDateTime(t, s);
    }
    final hasValue = s != null;

    final row = Row(
      children: [
        // Full ink, not muted. With no label above it ("When" was dropped
        // because the icon says it), this glyph IS the field's name — it
        // cannot be the faintest thing on the card.
        Icon(Icons.event_outlined, size: 18, color: AppColors.ink),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            // bodyMedium, a step under the description's bodyLarge. When
            // when/where/what all shared one size the page had no hierarchy:
            // the description is the content, these two are its facts.
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: hasValue ? AppColors.ink : AppColors.inkMuted,
            ),
          ),
        ),
        // No edit pen — see InlineEditableText for why.
      ],
    );

    if (!canEdit) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: row,
      );
    }
    return InkWell(
      onTap: () =>
          event.isTrip ? _editRange(context, ref) : _editSingle(context, ref),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: row,
      ),
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
    await ref
        .read(editEventControllerProvider.notifier)
        .save(event.id, startsAt: start, endsAt: end, clearEndsAt: end == null);
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
      day.year,
      day.month,
      day.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
    await ref
        .read(editEventControllerProvider.notifier)
        .save(event.id, startsAt: dt, clearEndsAt: true);
  }
}
