/// ActivityItem — a single Home-feed entry, built from a member-visible row.
/// Not a table mirror (entries come from several tables), so it's a plain
/// immutable class built from the query row shapes rather than a freezed model.
///
/// Every source table is RLS-scoped to event membership, so an activity can
/// only ever describe an event the reader already belongs to. A surprise target
/// is in none of those rows, so the event they are hidden from contributes
/// nothing here — the feed cannot become a side channel. Do not add a source
/// that isn't member-scoped.
library;

enum ActivityKind {
  comment,
  reply,
  pollClosed,
  pollReopened,
  attachment,

  /// Votes on ONE poll, collapsed into a single entry — see [voterNames].
  pollVoted,

  /// Someone said they're coming.
  rsvpGoing,

  /// Someone said they're not.
  rsvpNotGoing,

  /// Someone was added to an event.
  memberAdded,
}

class ActivityItem {
  const ActivityItem({
    required this.kind,
    required this.id,
    required this.createdAt,
    required this.eventId,
    required this.eventTitle,
    this.actorHandle,
    this.actorId,
    this.text,
    this.voterNames = const [],
    this.voterCount = 0,
    this.pollKind,
  });

  final ActivityKind kind;
  final String id;
  final DateTime createdAt;
  final String eventId;
  final String eventTitle;

  /// Who did it — `nickname#tagline`, or null if unknown.
  final String? actorHandle;

  /// Who did it, by id. Needed so own-actions can be dropped AFTER the feed has
  /// collapsed a poll's history to its latest state — see _latestPerPoll.
  /// Nullable because event_history.actor_id is.
  final String? actorId;

  /// Supporting detail: the comment body, the poll question, the filename.
  final String? text;

  /// For [ActivityKind.pollVoted]: up to two names to render inline. Beyond
  /// two the entry switches to a count, so the feed doesn't grow a list.
  final List<String> voterNames;

  /// For [ActivityKind.pollVoted]: how many distinct people voted.
  final int voterCount;

  /// For [ActivityKind.pollVoted]: 'time' | 'date' | 'place' | 'general'.
  final String? pollKind;

  /// Public alias so the feed's vote-grouping can build handles the same way.
  static String? handleOf(Map<String, dynamic>? p) => _handle(p);

  static String? _handle(Map<String, dynamic>? p) {
    final nick = p?['nickname'] as String?;
    final tag = p?['tagline'] as String?;
    return (nick != null && tag != null) ? '$nick#$tag' : null;
  }

  /// A top-level comment OR a reply — they are the same table, told apart by
  /// `parent_id`. Both were always in the feed; replies just used to be
  /// labelled as comments.
  factory ActivityItem.fromCommentRow(Map<String, dynamic> r) {
    final event = r['event'] as Map<String, dynamic>?;
    return ActivityItem(
      kind: r['parent_id'] == null ? ActivityKind.comment : ActivityKind.reply,
      id: r['id'] as String,
      createdAt: DateTime.parse(r['created_at'] as String),
      eventId: (event?['id'] as String?) ?? '',
      eventTitle: (event?['title'] as String?) ?? '',
      actorHandle: _handle(r['author'] as Map<String, dynamic>?),
      text: r['body'] as String?,
    );
  }

  /// A row of `event_history`. Only the poll kinds are surfaced in the feed —
  /// field edits stay in the event's own History panel, where they belong.
  static ActivityItem? fromHistoryRow(Map<String, dynamic> r) {
    final kind = switch (r['kind'] as String?) {
      'poll_closed' => ActivityKind.pollClosed,
      'poll_reopened' => ActivityKind.pollReopened,
      _ => null,
    };
    if (kind == null) return null;
    final event = r['event'] as Map<String, dynamic>?;
    return ActivityItem(
      kind: kind,
      id: r['id'] as String,
      createdAt: DateTime.parse(r['created_at'] as String),
      eventId: (event?['id'] as String?) ?? '',
      eventTitle: (event?['title'] as String?) ?? '',
      actorHandle: _handle(r['actor'] as Map<String, dynamic>?),
      actorId: r['actor_id'] as String?,
      // For a closed poll this is the winning label; for a reopen it's null.
      text: r['new_value'] as String?,
    );
  }

  /// An RSVP. Split going vs not-going so the feed can say which, and skipped
  /// entirely for 'pending'/'maybe' — "X hasn't decided" is not news.
  /// Ordered by `rsvp_at`, which is stamped only when the answer changes.
  static ActivityItem? fromRsvpRow(Map<String, dynamic> r) {
    final at = r['rsvp_at'] as String?;
    if (at == null) return null;
    final kind = switch (r['rsvp'] as String?) {
      'going' => ActivityKind.rsvpGoing,
      'declined' => ActivityKind.rsvpNotGoing,
      _ => null,
    };
    if (kind == null) return null;
    final event = r['event'] as Map<String, dynamic>?;
    final eventId = (event?['id'] as String?) ?? '';
    return ActivityItem(
      kind: kind,
      // event_members has a composite key, so synthesise a stable id.
      id: 'rsvp-$eventId-${r['user_id']}',
      createdAt: DateTime.parse(at),
      eventId: eventId,
      eventTitle: (event?['title'] as String?) ?? '',
      actorHandle: _handle(r['member'] as Map<String, dynamic>?),
    );
  }

  /// Someone joined an event. `created_at` on the membership row is exactly
  /// when they were added.
  factory ActivityItem.fromMemberRow(Map<String, dynamic> r) {
    final event = r['event'] as Map<String, dynamic>?;
    final eventId = (event?['id'] as String?) ?? '';
    return ActivityItem(
      kind: ActivityKind.memberAdded,
      id: 'member-$eventId-${r['user_id']}',
      createdAt: DateTime.parse(r['created_at'] as String),
      eventId: eventId,
      eventTitle: (event?['title'] as String?) ?? '',
      actorHandle: _handle(r['member'] as Map<String, dynamic>?),
    );
  }

  factory ActivityItem.fromAttachmentRow(Map<String, dynamic> r) {
    final event = r['event'] as Map<String, dynamic>?;
    return ActivityItem(
      kind: ActivityKind.attachment,
      id: r['id'] as String,
      createdAt: DateTime.parse(r['created_at'] as String),
      eventId: (event?['id'] as String?) ?? '',
      eventTitle: (event?['title'] as String?) ?? '',
      actorHandle: _handle(r['uploader'] as Map<String, dynamic>?),
      text: r['filename'] as String?,
    );
  }
}
