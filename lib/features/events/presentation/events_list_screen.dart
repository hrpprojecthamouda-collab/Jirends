/// Events — the Events branch of the app shell. Hosts a List / Agenda toggle.
/// Renders whatever [eventListProvider] returns; it does NOT decide what is
/// visible (that is the database's job). Loading and error states are handled
/// here, never swallowed.
///
/// Both views read the same RLS-scoped event list. The Agenda must never become
/// a free/busy overlay that leaks a hidden event's time — it only ever shows
/// the user's own visible events on their days.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/app_router.dart';
import '../../auth/application/auth_controller.dart';
import '../../notifications/presentation/widgets/notification_bell_button.dart';
import '../../profile/presentation/profile_avatar_button.dart';
import '../application/event_list_controller.dart';
import 'widgets/agenda_view.dart';
import 'widgets/event_card.dart';

enum _EventsView { list, agenda }

class EventsListScreen extends ConsumerStatefulWidget {
  const EventsListScreen({super.key});

  @override
  ConsumerState<EventsListScreen> createState() => _EventsListScreenState();
}

class _EventsListScreenState extends ConsumerState<EventsListScreen> {
  _EventsView _view = _EventsView.list;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final eventsAsync = ref.watch(eventListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const ProfileAvatarButton(),
        title: Text(t.eventsTitle),
        actions: const [NotificationBellButton()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_EventsView>(
                segments: [
                  ButtonSegment(
                    value: _EventsView.list,
                    icon: const Icon(Icons.view_list_outlined),
                    label: Text(t.eventsViewList),
                  ),
                  ButtonSegment(
                    value: _EventsView.agenda,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(t.eventsViewAgenda),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.createEvent),
        icon: const Icon(Icons.add),
        label: Text(t.eventsNew),
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: messageForError(err),
          retryLabel: t.commonRetry,
          onRetry: () => ref.invalidate(eventListProvider),
        ),
        data: (events) => switch (_view) {
          _EventsView.agenda => AgendaView(
              events: events,
              onOpenEvent: (e) => context.push(AppRoutes.eventDetail(e.id)),
            ),
          _EventsView.list => events.isEmpty
              ? _EmptyView(message: t.eventsEmpty)
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(eventListProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final event = events[i];
                      return EventCard(
                        event: event,
                        onTap: () =>
                            context.push(AppRoutes.eventDetail(event.id)),
                      );
                    },
                  ),
                ),
        },
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration_outlined,
                size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(message,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
