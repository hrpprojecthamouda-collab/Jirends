/// Two rules the Home feed has to get right, both found by code review.
///
///  1. A poll's close/reopen log is collapsed to its LATEST state before your
///     own actions are dropped. The other order lets a superseded entry from
///     someone else survive and describe the poll wrongly.
///  2. voterCount is people, you included; voterNames is other people only.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jirends/features/home/data/activity_item.dart';
import 'package:jirends/features/home/data/activity_repository.dart';

const _me = 'me';

Map<String, dynamic> _history({
  required String id,
  required String kind,
  required String actorId,
  required String pollId,
  required String at,
}) =>
    {
      'id': id,
      'kind': kind,
      'created_at': at,
      'new_value': null,
      'actor_id': actorId,
      'detail': {'poll_id': pollId},
      'actor': {'nickname': actorId, 'tagline': 'crew'},
      'event': {'id': 'e1', 'title': 'Apero'},
    };

Map<String, dynamic> _vote(String userId, String at) => {
      'id': '$userId-$at',
      'created_at': at,
      'poll_id': 'p1',
      'user_id': userId,
      'voter': {'nickname': userId, 'tagline': 'crew'},
      'poll': {'id': 'p1', 'kind': 'time'},
      'event': {'id': 'e1', 'title': 'Apero'},
    };

void main() {
  group('poll close/reopen', () {
    test('THE BUG: your reopen supersedes their close, silently', () {
      // Newest first, as PostgREST returns them.
      final rows = [
        _history(id: 'h2', kind: 'poll_reopened', actorId: _me,
            pollId: 'p1', at: '2026-08-20T11:00:00Z'),
        _history(id: 'h1', kind: 'poll_closed', actorId: 'moez',
            pollId: 'p1', at: '2026-08-20T10:00:00Z'),
      ];

      final items = latestPollStateChanges(rows, _me);

      // Moez's close is stale — you reopened it. And your reopen is your own
      // action. So the poll contributes NOTHING, rather than a false "Moez
      // closed a poll" while it sits open.
      expect(items, isEmpty);
    });

    test('someone else reopening after your close still shows', () {
      final rows = [
        _history(id: 'h2', kind: 'poll_reopened', actorId: 'moez',
            pollId: 'p1', at: '2026-08-20T11:00:00Z'),
        _history(id: 'h1', kind: 'poll_closed', actorId: _me,
            pollId: 'p1', at: '2026-08-20T10:00:00Z'),
      ];

      final items = latestPollStateChanges(rows, _me);

      expect(items, hasLength(1));
      expect(items.single.kind, ActivityKind.pollReopened);
      expect(items.single.actorHandle, 'moez#crew');
    });

    test('separate polls are collapsed separately', () {
      final rows = [
        _history(id: 'h2', kind: 'poll_closed', actorId: 'moez',
            pollId: 'p2', at: '2026-08-20T11:00:00Z'),
        _history(id: 'h1', kind: 'poll_closed', actorId: 'ana',
            pollId: 'p1', at: '2026-08-20T10:00:00Z'),
      ];

      expect(latestPollStateChanges(rows, _me), hasLength(2));
    });
  });

  group('vote grouping', () {
    test('voterCount counts you; voterNames does not name you', () {
      final items = groupVotesByPoll([
        _vote('moez', '2026-08-20T10:00:00Z'),
        _vote('ana', '2026-08-20T10:01:00Z'),
        _vote(_me, '2026-08-20T10:02:00Z'),
      ], _me);

      expect(items, hasLength(1));
      expect(items.single.voterCount, 3, reason: 'three people voted');
      expect(items.single.voterNames, ['moez', 'ana'].map((n) => '$n#crew'));
    });

    test('one person backing two options is still one voter', () {
      final items = groupVotesByPoll([
        _vote('moez', '2026-08-20T10:00:00Z'),
        _vote('moez', '2026-08-20T10:01:00Z'),
      ], _me);

      expect(items.single.voterCount, 1);
    });

    test('a poll only you voted on is dropped entirely', () {
      expect(groupVotesByPoll([_vote(_me, '2026-08-20T10:00:00Z')], _me),
          isEmpty);
    });
  });
}
