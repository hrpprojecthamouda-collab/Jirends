/// A single event in the list. Dumb: takes an [Event] and an onTap. Shows the
/// type, title, status phase, and date range if present. A surprise badge is
/// shown when surpriseTarget is set — this is only ever rendered for people who
/// can already see the event (organizers/members), never the target, so it
/// leaks nothing (the target never receives the row at all).
library;

import 'package:flutter/material.dart';

import '../../data/event.dart';

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, required this.onTap});

  final Event event;
  final VoidCallback onTap;

  IconData get _typeIcon => switch (event.eventType) {
        EventType.trip => Icons.luggage_outlined,
        EventType.dinner => Icons.restaurant_outlined,
        EventType.birthday => Icons.cake_outlined,
        EventType.meetup => Icons.groups_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dateText = _dateRange();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Icon(_typeIcon),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(event.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (event.isSurprise) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Surprise — hidden from its target',
                child: Icon(Icons.visibility_off_outlined,
                    size: 18, color: scheme.tertiary),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Pill(text: event.eventType.label),
                if (event.status != null) _Pill(text: _titleCase(event.status!)),
                if (dateText != null)
                  Text(dateText, style: textTheme.bodySmall),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  String? _dateRange() {
    final s = event.startsAt?.toLocal();
    if (s == null) return null;
    final start = _fmt(s);
    final e = event.endsAt?.toLocal();
    if (e == null) return start;
    return '$start → ${_fmt(e)}';
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSecondaryContainer)),
    );
  }
}
