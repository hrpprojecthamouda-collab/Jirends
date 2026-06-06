/// Event detail — STUB for this slice. It loads the single event (proving the
/// visibility model: a non-member who navigates here by id gets "not found",
/// indistinguishable from "doesn't exist") and shows its basic fields. The full
/// detail screen (members, items, comments, reactions, attachments, status
/// advance) is a later slice. No visibility logic lives here — the DB decided.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../application/event_list_controller.dart';
import '../data/event.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventByIdProvider(eventId));

    return Scaffold(
      appBar: AppBar(title: const Text('Event')),
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(messageForError(err))),
        data: (event) =>
            event == null ? const _NotFound() : _Detail(event: event),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'This event isn’t available.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(event.title, style: textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('${event.eventType.label}'
            '${event.status != null ? ' • ${event.status}' : ''}'),
        if (event.isSurprise) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.visibility_off_outlined,
                  size: 18, color: Theme.of(context).colorScheme.tertiary),
              const SizedBox(width: 6),
              const Text('Surprise — hidden from its target'),
            ],
          ),
        ],
        if (event.description != null && event.description!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(event.description!),
        ],
        const SizedBox(height: 24),
        Text(
          'Members, items, comments and the rest land in the next slice.',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}
