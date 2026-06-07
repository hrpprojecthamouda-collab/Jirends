/// Event detail — the real screen (replaces the old stub). Tabbed:
/// Overview / Members / Comments, for one event the user can see. All data is
/// RLS-scoped; this screen renders what the DB returns and never decides
/// visibility itself. A non-member who navigates here by id gets "unavailable"
/// (indistinguishable from "doesn't exist", by design).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/event_list_controller.dart';
import '../data/event.dart';
import '../data/event_member.dart';
import 'tabs/comments_tab.dart';
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

    return eventAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) =>
          Scaffold(appBar: AppBar(), body: Center(child: Text(messageForError(err)))),
      data: (event) {
        if (event == null) {
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
        return _DetailScaffold(event: event);
      },
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final typeColor = AppColors.forEventType(event.eventType);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
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
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: t.detailTabOverview),
              Tab(text: t.detailTabMembers),
              Tab(text: t.detailTabItems),
              Tab(text: t.detailTabComments),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            OverviewTab(event: event),
            MembersTab(event: event),
            ItemsTab(eventId: event.id),
            CommentsTab(eventId: event.id),
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
