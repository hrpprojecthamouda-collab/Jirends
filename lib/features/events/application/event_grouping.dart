/// Sorting and grouping for the events list. Pure functions over an
/// already-fetched list — this is PRESENTATION only.
///
/// Not to be confused with visibility (the cardinal rule): the database already
/// returned exactly the events this user may see, and every one of them lands
/// in some bucket here. Nothing is dropped, so switching views can never hide
/// an event the user is entitled to — it only decides which shelf it sits on.
///
/// `now` is always a parameter rather than DateTime.now() so the boundaries are
/// testable.
library;

import '../data/event.dart';

/// Which of the four top-level views an event belongs to.
enum EventBucket {
  /// Locked in: booked / confirmed / on_trip, still ahead of us.
  confirmed,

  /// Still soft: idea / planning, plus anything with no date yet.
  planning,

  /// Already happened, or reached a terminal "it's over" phase.
  past,

  /// Called off.
  cancelled,
}

/// Phases that mean "this is really happening". Trips use `booked`/`on_trip`;
/// dinners, birthdays and meetups use `confirmed` (see event_type_phases).
const _kConfirmedPhases = {'booked', 'confirmed', 'on_trip'};

/// Terminal phases meaning the event is over (as opposed to cancelled).
const _kFinishedPhases = {'done', 'celebrated'};

const _kCancelledPhase = 'cancelled';

/// Which view [event] belongs to. Order matters: cancelled wins over
/// everything (a called-off event is not "past" even if its date has gone),
/// then anything finished or in the past, then confirmed, then the rest.
EventBucket bucketOf(Event event, DateTime now) {
  if (event.status == _kCancelledPhase) return EventBucket.cancelled;
  if (_kFinishedPhases.contains(event.status)) return EventBucket.past;

  final starts = event.startsAt;
  // A trip is "past" only once its END has gone; everything else once its
  // single date has.
  final over = event.isTrip && event.endsAt != null
      ? event.endsAt!.isBefore(now)
      : starts != null && starts.isBefore(now);
  if (over) return EventBucket.past;

  if (_kConfirmedPhases.contains(event.status)) return EventBucket.confirmed;
  return EventBucket.planning;
}

/// Date bands within a view. Declaration order IS display order.
enum DateBand {
  /// No date chosen yet — shown first, because these are the ones waiting on
  /// someone to pick a day.
  undated,
  thisWeek,
  nextWeek,
  laterThisMonth,
  laterThisYear,
  beyond,

  /// Already gone. Never appears in the Confirmed/Planning views (those hold
  /// no past events by construction) — it exists for the "By me" view, which
  /// cuts across the buckets and so can contain history.
  past,
}

/// Midnight at the start of [d].
DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the week containing [d]. Weeks start Monday: the app ships
/// French and Tunisian alongside English, and both treat Monday as day one.
DateTime startOfWeek(DateTime d) =>
    _startOfDay(d).subtract(Duration(days: d.weekday - DateTime.monday));

/// Which band a date falls into, relative to [now].
DateBand bandFor(DateTime? startsAt, DateTime now) {
  if (startsAt == null) return DateBand.undated;
  // Matches bucketOf's notion of "gone", so a date can't be called past by one
  // and upcoming by the other.
  if (startsAt.isBefore(now)) return DateBand.past;

  final thisWeekStart = startOfWeek(now);
  final nextWeekStart = thisWeekStart.add(const Duration(days: 7));
  final weekAfterStart = nextWeekStart.add(const Duration(days: 7));
  final nextMonthStart = DateTime(now.year, now.month + 1);
  final nextYearStart = DateTime(now.year + 1);

  if (startsAt.isBefore(nextWeekStart)) return DateBand.thisWeek;
  if (startsAt.isBefore(weekAfterStart)) return DateBand.nextWeek;
  if (startsAt.isBefore(nextMonthStart)) return DateBand.laterThisMonth;
  if (startsAt.isBefore(nextYearStart)) return DateBand.laterThisYear;
  return DateBand.beyond;
}

/// One rendered section: a band and the events in it, already sorted.
class EventSection {
  const EventSection({required this.band, required this.events});
  final DateBand band;
  final List<Event> events;
}

/// Split [events] into the four views. Every event lands in exactly one.
Map<EventBucket, List<Event>> splitIntoBuckets(
  List<Event> events,
  DateTime now,
) {
  final out = {for (final b in EventBucket.values) b: <Event>[]};
  for (final e in events) {
    out[bucketOf(e, now)]!.add(e);
  }
  return out;
}

/// Which bucket to open on before the user has picked one: the first that has
/// anything in it, in enum order. Landing on an empty "Confirmed" makes the
/// app look broken for anyone who hasn't confirmed a plan yet, and enum order
/// means it snaps back to Confirmed as soon as something is.
EventBucket defaultBucket(Map<EventBucket, List<Event>> split) =>
    EventBucket.values.firstWhere(
      (b) => split[b]?.isNotEmpty ?? false,
      orElse: () => EventBucket.confirmed,
    );

/// Events created by [userId]. A CROSS-CUTTING filter, unlike [bucketOf]: an
/// event you created is also in exactly one of the four buckets, so this view
/// deliberately overlaps them rather than partitioning alongside them.
List<Event> createdBy(List<Event> events, String? userId) =>
    userId == null
        ? const []
        : [for (final e in events) if (e.createdBy == userId) e];

/// Group into date sections: undated first, then soonest to furthest, with
/// anything already gone last. Empty bands are omitted.
List<EventSection> dateSections(List<Event> events, DateTime now) {
  final byBand = <DateBand, List<Event>>{};
  for (final e in events) {
    byBand.putIfAbsent(bandFor(e.startsAt, now), () => []).add(e);
  }
  for (final entry in byBand.entries) {
    // History reads newest-first; everything ahead of us reads soonest-first.
    if (entry.key == DateBand.past) {
      entry.value.setAll(0, sortedNewestFirst(entry.value));
    } else {
      entry.value.sort(_soonestFirst);
    }
  }
  return [
    for (final band in DateBand.values)
      if (byBand[band]?.isNotEmpty ?? false)
        EventSection(band: band, events: byBand[band]!),
  ];
}

/// Past and cancelled read as history, so they run newest-first and get no
/// date bands ("upcoming this week" is meaningless for them).
List<Event> sortedNewestFirst(List<Event> events) {
  final copy = [...events];
  copy.sort((a, b) {
    final ad = a.startsAt, bd = b.startsAt;
    if (ad == null && bd == null) return b.createdAt.compareTo(a.createdAt);
    if (ad == null) return 1; // undated sinks below dated
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });
  return copy;
}

/// Soonest first; undated last; ties broken by title so the order is stable
/// between rebuilds rather than depending on fetch order.
int _soonestFirst(Event a, Event b) {
  final ad = a.startsAt, bd = b.startsAt;
  if (ad == null && bd == null) return a.title.compareTo(b.title);
  if (ad == null) return 1;
  if (bd == null) return -1;
  final byDate = ad.compareTo(bd);
  return byDate != 0 ? byDate : a.title.compareTo(b.title);
}
