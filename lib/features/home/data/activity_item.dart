/// ActivityItem — a single Home-feed entry derived from a member-visible row
/// (a comment or an event item). Not a table mirror, so it's a plain immutable
/// class built from the two query row shapes rather than a freezed model.
library;

enum ActivityKind { comment, item }

class ActivityItem {
  const ActivityItem({
    required this.kind,
    required this.id,
    required this.createdAt,
    required this.eventId,
    required this.eventTitle,
    this.actorHandle,
    this.text,
  });

  final ActivityKind kind;
  final String id;
  final DateTime createdAt;
  final String eventId;
  final String eventTitle;

  /// Who did it (for comments) — `nickname#tagline`, or null if unknown.
  final String? actorHandle;

  /// The comment body, or the item title.
  final String? text;

  factory ActivityItem.fromCommentRow(Map<String, dynamic> r) {
    final author = r['author'] as Map<String, dynamic>?;
    final event = r['event'] as Map<String, dynamic>?;
    final nick = author?['nickname'] as String?;
    final tag = author?['tagline'] as String?;
    return ActivityItem(
      kind: ActivityKind.comment,
      id: r['id'] as String,
      createdAt: DateTime.parse(r['created_at'] as String),
      eventId: (event?['id'] as String?) ?? '',
      eventTitle: (event?['title'] as String?) ?? '',
      actorHandle: (nick != null && tag != null) ? '$nick#$tag' : null,
      text: r['body'] as String?,
    );
  }

  factory ActivityItem.fromItemRow(Map<String, dynamic> r) {
    final event = r['event'] as Map<String, dynamic>?;
    return ActivityItem(
      kind: ActivityKind.item,
      id: r['id'] as String,
      createdAt: DateTime.parse(r['created_at'] as String),
      eventId: (event?['id'] as String?) ?? '',
      eventTitle: (event?['title'] as String?) ?? '',
      text: r['title'] as String?,
    );
  }
}
