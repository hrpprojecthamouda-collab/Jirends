/// Event detail — the real screen (replaces the old stub). Tabbed:
/// Overview / Members / Comments, for one event the user can see. All data is
/// RLS-scoped; this screen renders what the DB returns and never decides
/// visibility itself. A non-member who navigates here by id gets "unavailable"
/// (indistinguishable from "doesn't exist", by design).
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
import 'tabs/comments_tab.dart';
import 'tabs/files_tab.dart';
import 'tabs/items_tab.dart';
import 'tabs/members_tab.dart';
import 'tabs/overview_tab.dart';
import 'tabs/polls_tab.dart';

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

  String _typeLabel(AppLocalizations t) => switch (event.eventType) {
        EventType.trip => t.eventTypeTrip,
        EventType.dinner => t.eventTypeDinner,
        EventType.birthday => t.eventTypeBirthday,
        EventType.meetup => t.eventTypeMeetup,
      };

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

  static const int _filesTabIndex = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final typeColor = AppColors.forEventType(event.eventType);
    final myId = ref.watch(currentUserIdProvider);
    final members = ref.watch(eventMembersProvider(event.id)).value ?? const [];
    final canEdit = isCurrentUserOrganizer(members, myId);
    // The signed-in user's own membership row (for the RSVP follow button).
    final myMembership =
        members.where((m) => m.userId == myId).firstOrNull;

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        // ── JIRA-ticket header row: back (auto) + Attachment + ⋮ + RSVP ──
        appBar: AppBar(
          titleSpacing: 0,
          actions: [
            // Attachment: its own button -> jump to the Files tab.
            Builder(
              builder: (context) => IconButton(
                tooltip: t.eventAttachment,
                icon: const Icon(Icons.attach_file),
                onPressed: () =>
                    DefaultTabController.of(context).animateTo(_filesTabIndex),
              ),
            ),
            // Overflow: Share / Copy link / Delete (delete organizer-only).
            _OverflowMenu(event: event, canDelete: canEdit),
            // RSVP follow / following (only for members).
            if (myMembership != null)
              _FollowButton(event: event, membership: myMembership),
            const SizedBox(width: 4),
          ],
          // ── Title + status below the header ──────────────────────────
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(132),
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
                        if (event.isSurprise)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.visibility_off_outlined,
                                size: 18, color: AppColors.yellow),
                          ),
                        if (canEdit)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.edit_outlined,
                                size: 16, color: AppColors.inkMuted),
                          ),
                      ],
                    ),
                  ),
                ),
                // Type label + status button row.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Text(_typeLabel(t),
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: typeColor)),
                      const Spacer(),
                      _StatusChip(event: event, canEdit: canEdit),
                    ],
                  ),
                ),
                TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: t.detailTabOverview),
                    Tab(text: t.detailTabMembers),
                    Tab(text: t.detailTabItems),
                    Tab(text: t.detailTabPolls),
                    Tab(text: t.detailTabComments),
                    Tab(text: t.detailTabFiles),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            OverviewTab(event: event),
            MembersTab(event: event),
            ItemsTab(eventId: event.id),
            PollsTab(eventId: event.id),
            CommentsTab(eventId: event.id),
            FilesTab(eventId: event.id),
          ],
        ),
      ),
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
      child: TextButton.icon(
        onPressed: () => ref
            .read(memberActionsControllerProvider.notifier)
            .setMyRsvp(event.id,
                following ? RsvpStatus.declined : RsvpStatus.going),
        icon: Icon(following ? Icons.star : Icons.star_border, size: 18),
        label: Text(following ? t.eventFollowing : t.eventFollow),
        style: TextButton.styleFrom(
          foregroundColor: following ? AppColors.violet : AppColors.inkMuted,
        ),
      ),
    );
  }
}

/// Overflow menu: Share, Copy link, and (organizer-only) Delete. The link is a
/// deep link to the event; it only opens for people who are already members
/// (RLS), so it's a convenience, not a public share.
class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.event, required this.canDelete});
  final Event event;
  final bool canDelete;

  String get _link => 'https://jirends.app/events/${event.id}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        switch (v) {
          case 'share':
            await SharePlus.instance
                .share(ShareParams(text: '${t.eventShareText(event.title)}\n$_link'));
          case 'copy':
            await Clipboard.setData(ClipboardData(text: _link));
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
        PopupMenuItem(value: 'share', child: Text(t.eventShare)),
        PopupMenuItem(value: 'copy', child: Text(t.eventCopyLink)),
        if (canDelete) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: Text(t.eventDelete,
                style: const TextStyle(color: AppColors.coral)),
          ),
        ],
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
                    ? const Icon(Icons.check, color: AppColors.violet)
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
          icon: const Icon(Icons.close, color: AppColors.coral),
          onPressed: () => Navigator.of(context).pop(),
        ),
        IconButton(
          tooltip: t.commonAdd,
          icon: const Icon(Icons.check, color: AppColors.teal),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
    );
  }
}
