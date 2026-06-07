/// Agenda view — a month calendar (table_calendar) with a dot on each day that
/// has one or more of YOUR events, and below it the selected day's events.
///
/// CARDINAL-RULE NOTE: this reads only [eventListProvider] (RLS-scoped to the
/// user's visible events). It is NOT a free/busy overlay — it never shows or
/// infers anything about events the user can't see. A surprise hidden from the
/// user simply isn't in the list, so it never appears on any day.
library;

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/event.dart';
import 'event_card.dart';

class AgendaView extends StatefulWidget {
  const AgendaView({
    super.key,
    required this.events,
    required this.onOpenEvent,
  });

  final List<Event> events;
  final void Function(Event) onOpenEvent;

  @override
  State<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<AgendaView> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = _dateOnly(DateTime.now());

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Events that fall on [day], by their local start date.
  List<Event> _eventsOn(DateTime day) {
    final d = _dateOnly(day);
    return widget.events.where((e) {
      final s = e.startsAt?.toLocal();
      return s != null && _dateOnly(s) == d;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final selected = _eventsOn(_selectedDay);

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TableCalendar<Event>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2035, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
              eventLoader: _eventsOn,
              startingDayOfWeek: StartingDayOfWeek.monday,
              availableCalendarFormats: const {CalendarFormat.month: 'Month'},
              onDaySelected: (selectedDay, focusedDay) => setState(() {
                _selectedDay = _dateOnly(selectedDay);
                _focusedDay = focusedDay;
              }),
              calendarStyle: const CalendarStyle(
                outsideDaysVisible: false,
                defaultTextStyle: TextStyle(color: AppColors.ink),
                weekendTextStyle: TextStyle(color: AppColors.inkMuted),
                todayDecoration: BoxDecoration(
                  color: AppColors.surfaceHi,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: AppColors.violet,
                  shape: BoxShape.circle,
                ),
                markerDecoration: BoxDecoration(
                  color: AppColors.teal,
                  shape: BoxShape.circle,
                ),
                markersMaxCount: 3,
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle:
                    TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
                leftChevronIcon:
                    Icon(Icons.chevron_left, color: AppColors.inkMuted),
                rightChevronIcon:
                    Icon(Icons.chevron_right, color: AppColors.inkMuted),
              ),
              daysOfWeekStyle: const DaysOfWeekStyle(
                weekdayStyle: TextStyle(color: AppColors.inkMuted),
                weekendStyle: TextStyle(color: AppColors.inkMuted),
              ),
            ),
          ),
        ),
        Expanded(
          child: selected.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(t.agendaNoEventsOnDay,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.inkMuted)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  children: [
                    for (final e in selected)
                      EventCard(event: e, onTap: () => widget.onOpenEvent(e)),
                  ],
                ),
        ),
      ],
    );
  }
}
