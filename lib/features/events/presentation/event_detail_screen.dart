/// Event detail — the real screen (replaces the old stub). Tabbed:
/// Overview / Members / Comments, for one event the user can see. All data is
/// RLS-scoped; this screen renders what the DB returns and never decides
/// visibility itself. A non-member who navigates here by id gets "unavailable"
/// (indistinguishable from "doesn't exist", by design).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/event_detail_controller.dart';
import '../application/event_list_controller.dart';
import '../data/event.dart';
import '../data/event_member.dart';
import 'tabs/comments_tab.dart';
import 'tabs/files_tab.dart';
import 'tabs/items_tab.dart';
import 'tabs/members_tab.dart';
import 'tabs/overview_tab.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final eventAsync = ref.watch(eventByIdProvider(eventId));

    // Surface edit errors here (top level) so they show regardless of which tab
    // is active, and so the edit controller is always observed (never disposed
    // mid-save). The previous event value is kept during a refresh so the
    // screen doesn't collapse to a spinner after a save invalidates it.
    ref.listen(editEventControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(next.error!))));
      }
    });

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final typeColor = AppColors.forEventType(event.eventType);
    final myId = ref.watch(currentUserIdProvider);
    final members = ref.watch(eventMembersProvider(event.id)).value ?? const [];
    final canEdit = isCurrentUserOrganizer(members, myId);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: InkWell(
            onTap: canEdit ? () => _editTitle(context, ref) : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(event.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Row(
                        children: [
                          Text(_typeLabel(t),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: typeColor)),
                          if (event.isSurprise) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.visibility_off_outlined,
                                size: 14, color: AppColors.yellow),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (canEdit) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_outlined,
                      size: 16, color: AppColors.inkMuted),
                ],
              ],
            ),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: t.detailTabOverview),
              Tab(text: t.detailTabMembers),
              Tab(text: t.detailTabItems),
              Tab(text: t.detailTabComments),
              Tab(text: t.detailTabFiles),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            OverviewTab(event: event),
            MembersTab(event: event),
            ItemsTab(eventId: event.id),
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
