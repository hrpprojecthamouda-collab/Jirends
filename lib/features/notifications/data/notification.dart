/// AppNotification — one row of public.notifications, joined to the actor's
/// profile and (for event kinds) the event title. The first
/// PER-RECIPIENT table in the app: RLS scopes reads to your own rows only.
/// Written only by SECURITY DEFINER triggers, never by the client (except
/// marking read_at on your own rows).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/data/profile.dart';

part 'notification.freezed.dart';
part 'notification.g.dart';

/// The kinds of notification. Unknown strings fall back to [NotificationKind.other].
enum NotificationKind {
  friendAdded,
  eventMemberAdded,
  eventCancelled,
  eventConfirmed,
  expenseAdded,

  /// Somebody tagged you in a comment. Only ever sent to event MEMBERS —
  /// see comment_mentions.sql for why that is a hard rule, not a nicety.
  commentMention,
  other;

  static NotificationKind fromRaw(String raw) => switch (raw) {
        'friend_added' => NotificationKind.friendAdded,
        'event_member_added' => NotificationKind.eventMemberAdded,
        'event_cancelled' => NotificationKind.eventCancelled,
        'event_confirmed' => NotificationKind.eventConfirmed,
        'expense_added' => NotificationKind.expenseAdded,
        'comment_mention' => NotificationKind.commentMention,
        _ => NotificationKind.other,
      };
}

@freezed
abstract class AppNotification with _$AppNotification {
  const AppNotification._();

  const factory AppNotification({
    required String id,
    required String recipientId,
    String? actorId,
    required String kind,
    String? eventId,
    /// The comment the mention was in (comment_mention only).
    String? commentId,
    DateTime? readAt,
    required DateTime createdAt,
    Profile? actor,
    /// Title-only embed of the related event (event_* kinds), if any.
    NotificationEventRef? event,
  }) = _AppNotification;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      _$AppNotificationFromJson(json);

  NotificationKind get kindEnum => NotificationKind.fromRaw(kind);

  bool get isUnread => readAt == null;
}

@freezed
abstract class NotificationEventRef with _$NotificationEventRef {
  const factory NotificationEventRef({
    required String id,
    required String title,
  }) = _NotificationEventRef;

  factory NotificationEventRef.fromJson(Map<String, dynamic> json) =>
      _$NotificationEventRefFromJson(json);
}
