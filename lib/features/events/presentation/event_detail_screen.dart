/// Event detail — one scrollable page, no tabs. The header carries Share, the
/// Toolbox (Expenses Center / History / copy link / delete) and the RSVP
/// heart; everything else lives in the page itself (see overview_tab.dart):
/// when/where, description, host + attendees, polls, comments, files. The
/// roster, polls and toolbox destinations open as overlay panels
/// ([showEventOverlaySheet]) rather than separate screens.
///
/// All data is RLS-scoped; this screen renders what the DB returns and never
/// decides visibility itself. A non-member who navigates here by id gets
/// "unavailable" (indistinguishable from "doesn't exist", by design).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/event_detail_controller.dart';
import '../application/event_list_controller.dart';
import '../application/event_status_controller.dart';
import '../data/event.dart';
import '../data/event_member.dart';
import '../data/event_phase.dart';
import 'tabs/expenses_tab.dart';
import 'tabs/history_tab.dart';
import 'tabs/overview_tab.dart';
import 'widgets/event_overlay_sheet.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final eventAsync = ref.watch(eventByIdProvider(eventId));

    // Surface edit + status errors here (top level) so they show regardless of
    // which tab is active, and so those controllers are always observed (never
    // disposed mid-action). The previous event value is kept during a refresh so
    // the screen doesn't collapse to a spinner after an action invalidates it.
    void onActionError(_, AsyncValue next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(next.error!))));
      }
    }

    ref.listen(editEventControllerProvider, onActionError);
    ref.listen(eventStatusControllerProvider, onActionError);

    // Keep showing the last known event while a refresh is in flight; only show
    // the spinner on the very first load (no value yet).
    final event = eventAsync.value;
    if (event != null) return _DetailScaffold(event: event);

    if (eventAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (eventAsync.hasError) {
      return Scaffold(
          appBar: AppBar(),
          body: Center(child: Text(messageForError(eventAsync.error!))));
    }
    // Loaded but null => not visible / doesn't exist.
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t.eventsUnavailable, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _DetailScaffold extends ConsumerWidget {
  const _DetailScaffold({required this.event});
  final Event event;

  /// Inline title edit via a small dialog (the AppBar is too cramped for an
  /// in-place editor). Organizer-only; RLS enforces regardless. We capture the
  /// notifier BEFORE the await so we never touch this widget's `ref`/`context`
  /// after the dialog closes and the detail screen rebuilds. The dialog's text
  /// controller is owned by [_TitleEditDialog] (a StatefulWidget) so it is
  /// disposed only after the route is fully gone — disposing it here, right
  /// after the await, fires the framework's `_dependents.isEmpty` assertion
  /// because the dismissing TextField still depends on it.
  Future<void> _editTitle(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(editEventControllerProvider.notifier);
    final eventId = event.id;
    final currentTitle = event.title;
    final newTitle = await showDialog<String>(
      context: context,
      builder: (_) => _TitleEditDialog(initial: currentTitle),
    );
    if (newTitle == null || newTitle.isEmpty || newTitle == currentTitle) return;
    await notifier.save(eventId, title: newTitle);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserIdProvider);
    final members = ref.watch(eventMembersProvider(event.id)).value ?? const [];
    final canEdit = isCurrentUserOrganizer(members, myId);
    // The signed-in user's own membership row (for the RSVP follow button).
    final myMembership =
        members.where((m) => m.userId == myId).firstOrNull;

    return Scaffold(
      // ── Header row: back (auto) + Share + Toolbox + RSVP ──────────────
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          _ShareButton(event: event),
          _ToolboxMenu(event: event, canDelete: canEdit),
          // RSVP follow / following (only for members).
          if (myMembership != null)
            _FollowButton(event: event, membership: myMembership),
          const SizedBox(width: 4),
        ],
        // ── Title + status below the header ──────────────────────────
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(84),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: InkWell(
                  onTap: canEdit ? () => _editTitle(context, ref) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(event.title,
                            style: Theme.of(context).textTheme.headlineSmall),
                      ),
                      // No edit pen. The whole row is still the tap target
                      // for organizers; the icon only cost width that a long
                      // title needed more.
                    ],
                  ),
                ),
              ),
              // Status, on the left where the type label used to sit. The
              // event type isn't shown at all: it only picks the template
              // (phases + fields) at creation time and says nothing useful
              // about the event afterwards.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    _StatusChip(event: event, canEdit: canEdit),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // No tabs: the event is one scrollable page. Polls and the member roster
      // open as overlay panels from within it; Expenses and History live in
      // the toolbox; Files renders at the bottom of the page.
      body: OverviewTab(event: event),
    );
  }
}

/// Whether the current user is an organizer of [event], derived from the live
/// member list. Shared by tabs to gate organizer-only actions in the UI (RLS
/// enforces regardless).
bool isCurrentUserOrganizer(
    List<EventMember> members, String? myUserId) {
  return members.any((m) => m.userId == myUserId && m.isOrganizer);
}

/// Follow/Unfollow as RSVP: "Follow" sets the caller's RSVP to going,
/// "Following" (tap) sets it to declined. Reuses event_members.rsvp via the
/// member-actions controller — no new backend concept.
class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.event, required this.membership});
  final Event event;
  final EventMember membership;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final following = membership.rsvp == RsvpStatus.going;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IconButton(
        tooltip: following ? t.eventFollowing : t.eventFollow,
        onPressed: () => ref
            .read(memberActionsControllerProvider.notifier)
            .setMyRsvp(event.id,
                following ? RsvpStatus.declined : RsvpStatus.going),
        icon: Icon(following ? Icons.favorite : Icons.favorite_border, size: 18),
        color: following ? AppColors.primary : AppColors.inkMuted,
      ),
    );
  }
}

/// Deep link to the event. It only opens for people who are already members
/// (RLS), so sharing it is a convenience, not a public share.
String _eventLink(Event event) => 'https://jirends.app/events/${event.id}';

/// Share — promoted out of the old overflow menu to a first-class button.
/// Long-press copies the link instead of opening the share sheet.
class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final link = _eventLink(event);
    return IconButton(
      tooltip: t.eventShare,
      icon: const Icon(Icons.ios_share),
      onPressed: () => SharePlus.instance
          .share(ShareParams(text: '${t.eventShareText(event.title)}\n$link')),
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: link));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(t.eventLinkCopied)));
        }
      },
    );
  }
}

/// Toolbox — the secondary destinations that no longer warrant a tab:
/// Expenses Center and History, each opening as an overlay panel. Copy link
/// and (organizer-only) Delete live here too, since they're event-level
/// utilities rather than content.
class _ToolboxMenu extends ConsumerWidget {
  const _ToolboxMenu({required this.event, required this.canDelete});
  final Event event;
  final bool canDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      tooltip: t.eventToolbox,
      icon: const Icon(Icons.handyman_outlined),
      onSelected: (v) async {
        switch (v) {
          case 'expenses':
            await showEventOverlaySheet(
              context,
              title: t.detailTabExpenses,
              child: ExpensesTab(eventId: event.id),
            );
          case 'history':
            await showEventOverlaySheet(
              context,
              title: t.detailTabHistory,
              child: HistoryTab(eventId: event.id),
            );
          case 'copy':
            await Clipboard.setData(ClipboardData(text: _eventLink(event)));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text(t.eventLinkCopied)));
            }
          case 'delete':
            await _confirmDelete(context, ref);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'expenses',
          child: Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 18),
            const SizedBox(width: 12),
            Text(t.detailTabExpenses),
          ]),
        ),
        PopupMenuItem(
          value: 'history',
          child: Row(children: [
            const Icon(Icons.history, size: 18),
            const SizedBox(width: 12),
            Text(t.detailTabHistory),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'copy',
          child: Row(children: [
            const Icon(Icons.link, size: 18),
            const SizedBox(width: 12),
            Text(t.eventCopyLink),
          ]),
        ),
        if (canDelete)
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete_outline, size: 18, color: AppColors.coral),
              const SizedBox(width: 12),
              Text(t.eventDelete,
                  style: TextStyle(color: AppColors.coral)),
            ]),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final notifier = ref.read(editEventControllerProvider.notifier);
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(t.eventDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.eventDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await notifier.delete(event.id);
    if (ok) router.pop(); // back to the events list
  }
}

/// The current-status chip shown top-right in the app bar. Tinted by the phase;
/// organizers tap it to advance the event to another phase (a bottom sheet of
/// the type's phases). Read-only for non-organizers. The phase LABEL comes from
/// event_type_phases (config), falling back to the raw key while loading.
class _StatusChip extends ConsumerWidget {
  const _StatusChip({required this.event, required this.canEdit});
  final Event event;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phasesAsync = ref.watch(eventPhasesProvider(event.eventType));
    final phases = phasesAsync.value ?? const <EventPhase>[];
    final color = AppColors.forPhaseKey(event.status);
    final label = _labelFor(event.status, phases);

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
          if (canEdit) ...[
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: color),
          ],
        ],
      ),
    );

    // NOTE: no Center/Align here — this chip sits as a non-flex child of the
    // header Row, and an Align/Center child in a Row is given unbounded width,
    // which it tries to fill -> "BoxConstraints forces an infinite width". The
    // chip sizes itself (Row mainAxisSize.min), so return it directly.
    return canEdit
        ? InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _advance(context, ref, phases),
            child: chip,
          )
        : chip;
  }

  String _labelFor(String? key, List<EventPhase> phases) {
    if (key == null) return '…';
    for (final p in phases) {
      if (p.key == key) return p.label;
    }
    // Fallback: title-case the raw key.
    return key.isEmpty
        ? key
        : key[0].toUpperCase() + key.substring(1).replaceAll('_', ' ');
  }

  Future<void> _advance(
      BuildContext context, WidgetRef ref, List<EventPhase> phases) async {
    final notifier = ref.read(eventStatusControllerProvider.notifier);
    final eventId = event.id;
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in phases)
              ListTile(
                leading: Icon(Icons.circle,
                    size: 12, color: AppColors.forPhaseKey(p.key)),
                title: Text(p.label),
                trailing: event.status == p.key
                    ? Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(p.key),
              ),
          ],
        ),
      ),
    );
    if (key == null || key == event.status) return;
    await notifier.advance(eventId, key);
  }
}

/// A tiny title-edit dialog that OWNS its TextEditingController and disposes it
/// in its own dispose() — i.e. only after the route is fully removed. Pops with
/// the trimmed title (or null on cancel).
class _TitleEditDialog extends StatefulWidget {
  const _TitleEditDialog({required this.initial});
  final String initial;

  @override
  State<_TitleEditDialog> createState() => _TitleEditDialogState();
}

class _TitleEditDialogState extends State<_TitleEditDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.createFieldTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 140,
        decoration: const InputDecoration(counterText: ''),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        IconButton(
          tooltip: t.commonCancel,
          icon: Icon(Icons.close, color: AppColors.coral),
          onPressed: () => Navigator.of(context).pop(),
        ),
        IconButton(
          tooltip: t.commonAdd,
          icon: Icon(Icons.check, color: AppColors.teal),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
    );
  }
}
