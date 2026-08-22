/// A single event in the list: an outlined card with a solid header bar
/// carrying when and where, then the title in bold, then the status and
/// attendee count in plain weight.
///
/// The card uses ONE colour — [AppColors.primary] — regardless of status, so
/// the list reads as a set rather than a traffic-light. Being the brand token
/// it follows the palette chosen in Settings, and it has to clear contrast
/// three ways: the bar against the app background, the outline against the
/// card body, and white-ish text on the bar. Measured across every shipped
/// palette the worst cases are 4.33:1, 4.87:1 and 4.74:1 respectively — all
/// pass. Re-check those three if a palette's primary is ever retuned.
///
/// Dumb: takes an [Event], an optional attendee count and an onTap.
///
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/util/weekday.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/event.dart';

class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.onTap,
    this.attendeeCount,
  });

  final Event event;
  final VoidCallback onTap;

  /// Null while the counts are still loading — the line just omits it rather
  /// than flashing a wrong number.
  final int? attendeeCount;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    // One colour for every card, whatever the status (see class doc).
    final accent = AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: accent, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(event: event, accent: accent),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statusAndAttendees(t),
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "Planning · 3 attendees" — either half is dropped when unavailable rather
  /// than rendering a stray separator.
  String _statusAndAttendees(AppLocalizations t) {
    final parts = <String>[
      if (event.status != null) _titleCase(event.status!),
      if (attendeeCount != null) t.membersAttendees(attendeeCount!),
    ];
    return parts.join('  ·  ');
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
}

/// The solid bar across the top: when on the left, where on the right, in
/// [AppColors.onAccent] on a fill of [accent].
class _Header extends StatelessWidget {
  const _Header({required this.event, required this.accent});
  final Event event;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.onAccent,
          fontWeight: FontWeight.w800,
        );
    final where = event.location?.trim();

    return Container(
      color: accent,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Icon(Icons.event_outlined, size: 15, color: AppColors.onAccent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _when(t),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (where != null && where.isNotEmpty) ...[
            const SizedBox(width: 10),
            Icon(Icons.place_outlined, size: 15, color: AppColors.onAccent),
            const SizedBox(width: 4),
            // Flexible, not Expanded: a short place shouldn't stretch, but a
            // long one must be allowed to shrink instead of overflowing.
            Flexible(
              child: Text(
                where,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Trips show a day range; everything else a single date + time. Each date
  /// is prefixed with its weekday — "Sat 30/08" answers "which day is that?"
  /// without the reader doing calendar arithmetic. Undated events say so
  /// rather than leaving the bar blank.
  String _when(AppLocalizations t) {
    final s = event.startsAt?.toLocal();
    if (s == null) return t.eventsGroupUndated;
    if (event.isTrip) {
      final e = event.endsAt?.toLocal();
      return e == null
          ? _day(t, s)
          : '${_day(t, s)} → ${_day(t, e)}';
    }
    return '${_day(t, s)}  ${_hm(s)}';
  }

  static String _day(AppLocalizations t, DateTime d) =>
      '${weekdayShort(t, d)} ${_fmt(d)}';

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
