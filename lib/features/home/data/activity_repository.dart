/// ActivityRepository — builds the Home feed from data the user can ALREADY
/// see: comments and replies, poll closures/reopenings, and uploaded files,
/// across the user's visible events.
///
/// YOUR OWN ACTIONS ARE EXCLUDED. A feed telling you what you just did is
/// noise — you were there. The bell has always worked this way (notify()
/// refuses when recipient == actor); this brings the feed in line. The filter
/// is on the ACTOR, not the subject: "you were added to an event" is somebody
/// else's action and still shows.
///
/// CARDINAL RULE: this is a derived view, not a new visibility path. Every
/// source table below is RLS-scoped to event membership, so we add no filters
/// and no joins that could surface a hidden event — a surprise the user is the
/// target of has no rows in any of them and therefore never appears here. Do
/// not "enrich" this with anything outside the member-scoped tables.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'activity_item.dart';

class ActivityRepository {
  ActivityRepository(this._client);
  final SupabaseClient _client;

  /// The most recent activity across the user's visible events, newest first,
  /// capped at [limit].
  ///
  /// Each source is fetched at [limit] and the merged list trimmed back, so a
  /// burst of one kind cannot crowd the others out of the window entirely.
  Future<List<ActivityItem>> fetchRecent({int limit = 30}) async {
    final me = _client.auth.currentUser?.id;
    try {
      // Where the actor column is NOT NULL the filter runs server-side, so a
      // burst of your own activity can't fill the window and starve everyone
      // else's out of it. Nullable actor columns (event_history.actor_id,
      // event_members.added_by) are filtered in Dart instead: `neq` treats
      // NULL as non-matching and would silently drop those rows entirely.
      final results = await Future.wait([
        // Comments AND replies — the same table, told apart by parent_id.
        _client
            .from('comments')
            .select('id, created_at, body, parent_id, '
                'author:profiles!comments_author_id_fkey(nickname, tagline), '
                'event:events!comments_event_id_fkey(id, title)')
            .neq('author_id', me ?? '')
            .order('created_at', ascending: false)
            .limit(limit),
        // Poll closures/reopenings are already written to event_history by the
        // poll RPCs, so the feed reads those rows rather than duplicating the
        // write. They stay in the event's History panel as well — the same
        // activity surfaced in two places, not moved from one to the other.
        _client
            .from('event_history')
            .select('id, created_at, kind, new_value, actor_id, detail, '
                'actor:profiles!event_history_actor_id_fkey(nickname, tagline), '
                'event:events!event_history_event_id_fkey(id, title)')
            .inFilter('kind', const ['poll_closed', 'poll_reopened'])
            .order('created_at', ascending: false)
            .limit(limit),
        _client
            .from('attachments')
            .select('id, created_at, filename, '
                'uploader:profiles!attachments_uploaded_by_fkey(nickname, tagline), '
                'event:events!attachments_event_id_fkey(id, title)')
            .neq('uploaded_by', me ?? '')
            .order('created_at', ascending: false)
            .limit(limit),
        // Votes, with the poll they belong to. Collapsed per poll below rather
        // than one entry per vote — see _groupVotes.
        _client
            .from('poll_votes')
            .select('id, created_at, poll_id, user_id, '
                'voter:profiles!poll_votes_user_id_fkey(nickname, tagline), '
                'poll:polls!poll_votes_poll_id_fkey(id, kind), '
                'event:events!poll_votes_event_id_fkey(id, title)')
            .order('created_at', ascending: false)
            .limit(limit * 3),
        // RSVPs. rsvp_at is stamped only when the answer actually changes, so
        // this is "answered", not "was invited".
        _client
            .from('event_members')
            .select('user_id, rsvp, rsvp_at, '
                'member:profiles!event_members_user_id_fkey(nickname, tagline), '
                'event:events!event_members_event_id_fkey(id, title)')
            .not('rsvp_at', 'is', null)
            // You set your own RSVP, so user_id is the actor here.
            .neq('user_id', me ?? '')
            .order('rsvp_at', ascending: false)
            .limit(limit),
        _client
            .from('event_members')
            .select('user_id, created_at, added_by, '
                'member:profiles!event_members_user_id_fkey(nickname, tagline), '
                'event:events!event_members_event_id_fkey(id, title)')
            .order('created_at', ascending: false)
            .limit(limit),
      ]);

      final items = <ActivityItem>[
        for (final r in results[0]) ActivityItem.fromCommentRow(r),
        ...latestPollStateChanges(
            results[1].cast<Map<String, dynamic>>(), me),
        for (final r in results[2]) ActivityItem.fromAttachmentRow(r),
        ...groupVotesByPoll(results[3], me),
        for (final r in results[4]) ?ActivityItem.fromRsvpRow(r),
        // added_by is nullable and is the ACTOR; the member named in the entry
        // is the subject. Someone adding you still shows — you didn't do it.
        for (final r in results[5])
          if (r['added_by'] != me) ActivityItem.fromMemberRow(r),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return items.take(limit).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

/// A poll's close/reopen history is a log, so a poll closed then reopened
/// leaves BOTH rows behind. Only the latest state is news — "X reopened the
/// poll" makes the earlier "X closed the poll" wrong, not just old — so keep
/// one entry per poll, the most recent, then drop it if [me] is the one who
/// did it.
///
/// THAT ORDER IS THE WHOLE POINT, and it is why dropping your own actions is
/// done in here rather than by the caller. Filtering first and collapsing
/// second resurrects a superseded entry: if Moez closed a poll and you
/// reopened it, removing your row leaves Moez's close as the newest survivor
/// and the feed announces a closed poll that is open. Collapsing first picks
/// your reopen as the poll's state, and only then is it dropped for being
/// yours — so the poll contributes nothing rather than something false.
///
/// Rows arrive newest-first, so the first sighting of a poll_id is its latest.
/// [me] is compared against actor_id, which is nullable — an actorless row is
/// nobody's own action and is kept.
@visibleForTesting
List<ActivityItem> latestPollStateChanges(
  List<Map<String, dynamic>> rows,
  String? me,
) {
  final seen = <String>{};
  final out = <ActivityItem>[];
  for (final r in rows) {
    final pollId =
        (r['detail'] as Map<String, dynamic>?)?['poll_id'] as String?;
    // No poll_id (shouldn't happen for these kinds) -> keep it rather than
    // silently dropping the entry.
    if (pollId != null && !seen.add(pollId)) continue;
    final item = ActivityItem.fromHistoryRow(r);
    if (item == null) continue;
    if (item.actorId != null && item.actorId == me) continue;
    out.add(item);
  }
  return out;
}

/// Collapse many vote rows into ONE entry per poll: "X and Y voted on the time
/// poll in Z", or a count past two. Without this a poll with six voters would
/// push six near-identical lines into the feed and bury everything else.
///
/// Distinct people, not rows — a member may back several options, so the same
/// person can appear more than once per poll.
@visibleForTesting
List<ActivityItem> groupVotesByPoll(List<dynamic> rows, String? me) {
  final byPoll = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    final row = r as Map<String, dynamic>;
    final pollId = (row['poll'] as Map<String, dynamic>?)?['id'] as String?;
    if (pollId != null) (byPoll[pollId] ??= []).add(row);
  }

  final out = <ActivityItem>[];
  for (final entry in byPoll.entries) {
    final rows = entry.value;
    final names = <String>[];
    // Distinct people, you included — a member may back several options, so
    // rows are not people.
    final voters = <String>{};
    DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
    var othersVoted = false;
    for (final r in rows) {
      // Your own vote never contributes a NAME (the feed is about what other
      // people did) and never on its own keeps the entry alive — but it does
      // count toward "5 people voted", so it goes in `voters`.
      final isMine = r['user_id'] == me;
      final handle = ActivityItem.handleOf(r['voter'] as Map<String, dynamic>?);
      final voterId = r['user_id'] as String?;
      if (voterId != null) voters.add(voterId);
      if (handle != null && !isMine && !names.contains(handle)) {
        names.add(handle);
        othersVoted = true;
      }
      final at = DateTime.parse(r['created_at'] as String);
      if (at.isAfter(latest)) latest = at;
    }
    // A poll only you voted on is your own action — drop it entirely.
    if (!othersVoted) continue;
    final event = rows.first['event'] as Map<String, dynamic>?;
    final poll = rows.first['poll'] as Map<String, dynamic>?;
    out.add(ActivityItem(
      kind: ActivityKind.pollVoted,
      id: 'poll-votes-${entry.key}',
      // The most recent vote — so a poll people are actively voting on keeps
      // rising rather than being pinned to whenever the first vote landed.
      createdAt: latest,
      eventId: (event?['id'] as String?) ?? '',
      eventTitle: (event?['title'] as String?) ?? '',
      voterNames: names.take(2).toList(),
      voterCount: voters.length,
      pollKind: poll?['kind'] as String?,
    ));
  }
  return out;
}

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return ActivityRepository(ref.watch(supabaseClientProvider));
});
