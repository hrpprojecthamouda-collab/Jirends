/// Events list — the home screen's real body. Renders whatever
/// [eventListProvider] returns; it does NOT decide what is visible (that is the
/// database's job). Loading and error states are handled here, never swallowed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/data/profile_repository.dart';
import '../../../routing/app_router.dart';
import '../application/event_list_controller.dart';
import 'widgets/event_card.dart';

class EventsListScreen extends ConsumerWidget {
  const EventsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventListProvider);
    final handle = ref.watch(myProfileProvider).value?.handle ?? '…';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jirends'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.createEvent),
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: messageForError(err),
          onRetry: () => ref.invalidate(eventListProvider),
        ),
        data: (events) => events.isEmpty
            ? _EmptyView(handle: handle)
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(eventListProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  itemCount: events.length,
                  itemBuilder: (context, i) {
                    final event = events[i];
                    return EventCard(
                      event: event,
                      onTap: () => context.push(AppRoutes.eventDetail(event.id)),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.handle});
  final String handle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration_outlined, size: 64),
            const SizedBox(height: 16),
            Text('Welcome, $handle',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'No events yet. Tap “New event” to plan a trip, dinner, '
              'birthday, or meetup with friends.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
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
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
