// Boundaries for the events-list grouping. `now` is fixed so the week/month/
// year edges are exercised deterministically rather than depending on the day
// the suite happens to run.
import 'package:flutter_test/flutter_test.dart';

import 'package:jirends/features/events/application/event_grouping.dart';
import 'package:jirends/features/events/data/event.dart';

// Wednesday 17 June 2026, 10:00. Its week runs Mon 15 -> Sun 21.
final _now = DateTime(2026, 6, 17, 10);

Event _e({
  String id = 'e',
  String title = 'Event',
  String? status = 'idea',
  DateTime? startsAt,
  DateTime? endsAt,
  EventType type = EventType.meetup,
}) =>
    Event(
      id: id,
      title: title,
      eventType: type,
      status: status,
      startsAt: startsAt,
      endsAt: endsAt,
      createdBy: 'u',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('bucketOf', () {
    test('cancelled wins even when the date has passed', () {
      final e = _e(status: 'cancelled', startsAt: DateTime(2026, 1, 1));
      expect(bucketOf(e, _now), EventBucket.cancelled);
    });

    test('cancelled wins even when the date is still ahead', () {
      final e = _e(status: 'cancelled', startsAt: DateTime(2026, 12, 1));
      expect(bucketOf(e, _now), EventBucket.cancelled);
    });

    test('confirmed phases are per-type: booked and on_trip are trips', () {
      expect(
        bucketOf(_e(status: 'booked', startsAt: DateTime(2026, 6, 18)), _now),
        EventBucket.confirmed,
      );
      expect(
        bucketOf(_e(status: 'on_trip', startsAt: DateTime(2026, 6, 18)), _now),
        EventBucket.confirmed,
      );
      expect(
        bucketOf(
            _e(status: 'confirmed', startsAt: DateTime(2026, 6, 18)), _now),
        EventBucket.confirmed,
      );
    });

    test('idea and planning are planning, including with no date', () {
      expect(bucketOf(_e(status: 'idea'), _now), EventBucket.planning);
      expect(bucketOf(_e(status: 'planning'), _now), EventBucket.planning);
      expect(
        bucketOf(_e(status: 'idea', startsAt: DateTime(2026, 8, 1)), _now),
        EventBucket.planning,
      );
    });

    test('a past date moves an event to past whatever its phase', () {
      expect(
        bucketOf(_e(status: 'idea', startsAt: DateTime(2026, 5, 1)), _now),
        EventBucket.past,
      );
      expect(
        bucketOf(_e(status: 'confirmed', startsAt: DateTime(2026, 5, 1)), _now),
        EventBucket.past,
      );
    });

    test('terminal phases are past even with a future date', () {
      expect(
        bucketOf(_e(status: 'done', startsAt: DateTime(2026, 12, 1)), _now),
        EventBucket.past,
      );
      expect(
        bucketOf(
            _e(status: 'celebrated', startsAt: DateTime(2026, 12, 1)), _now),
        EventBucket.past,
      );
    });

    test('a trip is past only once its END has gone, not its start', () {
      final running = _e(
        type: EventType.trip,
        status: 'on_trip',
        startsAt: DateTime(2026, 6, 15),
        endsAt: DateTime(2026, 6, 20),
      );
      expect(bucketOf(running, _now), EventBucket.confirmed,
          reason: 'a trip under way has started but is not over');

      final finished = _e(
        type: EventType.trip,
        status: 'booked',
        startsAt: DateTime(2026, 6, 1),
        endsAt: DateTime(2026, 6, 5),
      );
      expect(bucketOf(finished, _now), EventBucket.past);
    });
  });

  group('bandFor', () {
    test('no date sorts into its own band', () {
      expect(bandFor(null, _now), DateBand.undated);
    });

    test('through Sunday is this week; Monday starts next week', () {
      expect(bandFor(DateTime(2026, 6, 17, 23), _now), DateBand.thisWeek);
      expect(bandFor(DateTime(2026, 6, 21, 23, 59), _now), DateBand.thisWeek);
      expect(bandFor(DateTime(2026, 6, 22), _now), DateBand.nextWeek);
      expect(bandFor(DateTime(2026, 6, 28, 23, 59), _now), DateBand.nextWeek);
    });

    test('after next week but inside June is later this month', () {
      expect(bandFor(DateTime(2026, 6, 29), _now), DateBand.laterThisMonth);
      expect(bandFor(DateTime(2026, 6, 30, 23), _now), DateBand.laterThisMonth);
    });

    test('July through December is later this year', () {
      expect(bandFor(DateTime(2026, 7, 1), _now), DateBand.laterThisYear);
      expect(bandFor(DateTime(2026, 12, 31, 23), _now), DateBand.laterThisYear);
    });

    test('next year and beyond gets its own band', () {
      expect(bandFor(DateTime(2027, 1, 1), _now), DateBand.beyond);
    });

    test('week start is Monday', () {
      // Sunday 21 June still belongs to the week beginning Mon 15.
      expect(startOfWeek(DateTime(2026, 6, 21)), DateTime(2026, 6, 15));
      expect(startOfWeek(DateTime(2026, 6, 15)), DateTime(2026, 6, 15));
    });
  });

  group('sections and sorting', () {
    test('undated comes first, then soonest to furthest', () {
      final sections = dateSections([
        _e(id: '1', startsAt: DateTime(2026, 7, 5)),
        _e(id: '2'),
        _e(id: '3', startsAt: DateTime(2026, 6, 18)),
      ], _now);

      expect(sections.map((s) => s.band).toList(),
          [DateBand.undated, DateBand.thisWeek, DateBand.laterThisYear]);
    });

    test('events inside a band run soonest first', () {
      final sections = dateSections([
        _e(id: 'late', startsAt: DateTime(2026, 6, 20)),
        _e(id: 'early', startsAt: DateTime(2026, 6, 18)),
      ], _now);
      expect(sections.single.events.map((e) => e.id).toList(),
          ['early', 'late']);
    });

    test('empty bands are omitted', () {
      final sections =
          dateSections([_e(startsAt: DateTime(2026, 6, 18))], _now);
      expect(sections.length, 1);
      expect(sections.single.band, DateBand.thisWeek);
    });

    test('history runs newest first with undated last', () {
      final sorted = sortedNewestFirst([
        _e(id: 'old', startsAt: DateTime(2026, 1, 1)),
        _e(id: 'undated'),
        _e(id: 'recent', startsAt: DateTime(2026, 6, 1)),
      ]);
      expect(sorted.map((e) => e.id).toList(), ['recent', 'old', 'undated']);
    });
  });

  group('createdBy ("By me")', () {
    Event mine(String id, {DateTime? at, String? status = 'idea'}) => Event(
          id: id,
          title: id,
          eventType: EventType.meetup,
          status: status,
          startsAt: at,
          createdBy: 'me',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('keeps only what I created', () {
      final events = [
        mine('a'),
        _e(id: 'b'), // createdBy 'u'
        mine('c', at: DateTime(2026, 6, 18)),
      ];
      expect(createdBy(events, 'me').map((e) => e.id), ['a', 'c']);
    });

    test('is empty while the user id is unknown', () {
      expect(createdBy([mine('a')], null), isEmpty);
    });

    test('cuts ACROSS the buckets rather than partitioning with them', () {
      // One of mine in each bucket: planning, confirmed, past, cancelled.
      final events = [
        mine('planning'),
        mine('confirmed', at: DateTime(2026, 6, 18), status: 'confirmed'),
        mine('past', at: DateTime(2026, 1, 1)),
        mine('cancelled', status: 'cancelled'),
      ];
      final split = splitIntoBuckets(events, _now);
      // Each sits in exactly one bucket...
      for (final b in EventBucket.values) {
        expect(split[b]!.length, 1, reason: '$b');
      }
      // ...and all four also show under "By me".
      expect(createdBy(events, 'me').length, 4);
    });

    test('a past event of mine gets its own band, listed last', () {
      final sections = dateSections([
        mine('past', at: DateTime(2026, 1, 1)),
        mine('soon', at: DateTime(2026, 6, 18)),
        mine('undated'),
      ], _now);
      expect(sections.map((s) => s.band).toList(),
          [DateBand.undated, DateBand.thisWeek, DateBand.past]);
    });

    test('the past band runs newest first', () {
      final sections = dateSections([
        mine('older', at: DateTime(2026, 1, 1)),
        mine('newer', at: DateTime(2026, 5, 1)),
      ], _now);
      expect(sections.single.band, DateBand.past);
      expect(sections.single.events.map((e) => e.id).toList(),
          ['newer', 'older']);
    });
  });

  group('defaultBucket', () {
    test('skips an empty Confirmed and opens on Planning', () {
      final split = splitIntoBuckets([
        _e(id: 'a', status: 'idea'),
        _e(id: 'b', status: 'idea', startsAt: DateTime(2026, 1, 1)),
      ], _now);
      expect(split[EventBucket.confirmed], isEmpty);
      expect(defaultBucket(split), EventBucket.planning);
    });

    test('prefers Confirmed as soon as something is confirmed', () {
      final split = splitIntoBuckets([
        _e(id: 'a', status: 'idea'),
        _e(id: 'b', status: 'confirmed', startsAt: DateTime(2026, 6, 18)),
      ], _now);
      expect(defaultBucket(split), EventBucket.confirmed);
    });

    test('falls through to Past when only history exists', () {
      final split = splitIntoBuckets(
        [_e(id: 'a', status: 'idea', startsAt: DateTime(2026, 1, 1))],
        _now,
      );
      expect(defaultBucket(split), EventBucket.past);
    });

    test('falls back to Confirmed when there is nothing at all', () {
      expect(defaultBucket(splitIntoBuckets([], _now)), EventBucket.confirmed);
    });
  });

  test('every event lands in exactly one bucket — nothing is dropped', () {
    final events = [
      _e(id: 'a', status: 'idea'),
      _e(id: 'b', status: 'confirmed', startsAt: DateTime(2026, 6, 18)),
      _e(id: 'c', status: 'cancelled'),
      _e(id: 'd', status: 'idea', startsAt: DateTime(2026, 1, 1)),
      _e(id: 'e', status: 'done', startsAt: DateTime(2026, 12, 1)),
      _e(id: 'f', status: null),
    ];
    final split = splitIntoBuckets(events, _now);
    final total = split.values.fold<int>(0, (n, l) => n + l.length);
    expect(total, events.length,
        reason: 'the list is partitioned, never filtered');
    expect(split[EventBucket.planning]!.map((e) => e.id), contains('f'),
        reason: 'an unknown/null phase must still be reachable somewhere');
  });
}
