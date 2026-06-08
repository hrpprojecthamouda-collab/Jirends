/// A single event in the list. Dumb: takes an [Event] and an onTap. The leading
/// avatar and the type pill are tinted by the event's type; the status pill is
/// tinted by its phase (see AppColors maps), so the whole list reads at a glance.
///
/// A surprise badge is shown when surpriseTarget is set — this is only ever
/// rendered for people who can already see the event (organizers/members),
/// never the target, so it leaks nothing (the target never receives the row).
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
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
    final typeColor = AppColors.forEventType(event.eventType);
    final phaseColor = AppColors.forPhaseKey(event.status);
    final dateText = _dateRange();

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          // ignore: deprecated_member_use
          backgroundColor: typeColor.withOpacity(0.18),
          foregroundColor: typeColor,
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
                message: t.eventsSurpriseBadge,
                child: const Icon(Icons.visibility_off_outlined,
                    size: 18, color: AppColors.yellow),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Pill(text: _typeLabel(t), color: typeColor),
              if (event.status != null)
                _Pill(text: _titleCase(event.status!), color: phaseColor),
              if (dateText != null)
                Text(dateText,
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppColors.inkMuted)),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.inkMuted),
      ),
    );
  }

  String? _dateRange() {
    final s = event.startsAt?.toLocal();
    if (s == null) return null;
    // Trips show a day range; other types show their single date + time.
    if (event.isTrip) {
      final e = event.endsAt?.toLocal();
      return e == null ? _fmt(s) : '${_fmt(s)} → ${_fmt(e)}';
    }
    return '${_fmt(s)} ${_hm(s)}';
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
}

/// A small rounded chip tinted by [color], used for type and phase labels.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
