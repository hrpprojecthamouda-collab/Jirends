/// Event detail — STUB for this slice. It loads the single event (proving the
/// visibility model: a non-member who navigates here by id gets "not found",
/// indistinguishable from "doesn't exist") and shows its basic fields. The full
/// detail screen (members, items, comments, reactions, attachments, status
/// advance) is a later slice. No visibility logic lives here — the DB decided.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/event_list_controller.dart';
import '../data/event.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventByIdProvider(eventId));

    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.eventsTitle)),
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(messageForError(err))),
        data: (event) => event == null
            ? _NotFound(message: t.eventsUnavailable)
            : _Detail(event: event),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.event});
  final Event event;

  String _typeLabel(AppLocalizations t) => switch (event.eventType) {
        EventType.trip => t.eventTypeTrip,
        EventType.dinner => t.eventTypeDinner,
        EventType.birthday => t.eventTypeBirthday,
        EventType.meetup => t.eventTypeMeetup,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(event.title, style: textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('${_typeLabel(t)}'
            '${event.status != null ? ' • ${event.status}' : ''}'),
        if (event.isSurprise) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.visibility_off_outlined,
                  size: 18, color: AppColors.yellow),
              const SizedBox(width: 6),
              Text(t.eventsSurpriseBadge),
            ],
          ),
        ],
        if (event.description != null && event.description!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(event.description!),
        ],
      ],
    );
  }
}
