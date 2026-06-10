/// EventHistoryEntry — one row of public.event_history, joined to the actor's
/// profile. A read-only change-log entry (field edits + poll lifecycle), scoped
/// to event members by RLS. Written only by SECURITY DEFINER DB code.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/data/profile.dart';

part 'event_history_entry.freezed.dart';
part 'event_history_entry.g.dart';

/// The kinds of change we log. Unknown strings fall back to [HistoryKind.other].
enum HistoryKind {
  title,
  description,
  status,
  location,
  startsAt,
  endsAt,
  pollCreated,
  pollClosed,
  pollReopened,
  other;

  static HistoryKind fromRaw(String raw) => switch (raw) {
        'title' => HistoryKind.title,
        'description' => HistoryKind.description,
        'status' => HistoryKind.status,
        'location' => HistoryKind.location,
        'starts_at' => HistoryKind.startsAt,
        'ends_at' => HistoryKind.endsAt,
        'poll_created' => HistoryKind.pollCreated,
        'poll_closed' => HistoryKind.pollClosed,
        'poll_reopened' => HistoryKind.pollReopened,
        _ => HistoryKind.other,
      };

  bool get isPoll =>
      this == HistoryKind.pollCreated ||
      this == HistoryKind.pollClosed ||
      this == HistoryKind.pollReopened;
}

@freezed
abstract class EventHistoryEntry with _$EventHistoryEntry {
  const EventHistoryEntry._();

  const factory EventHistoryEntry({
    required String id,
    required String eventId,
    String? actorId,
    required String kind,
    String? oldValue,
    String? newValue,
    @Default(<String, dynamic>{}) Map<String, dynamic> detail,
    required DateTime createdAt,
    Profile? actor,
  }) = _EventHistoryEntry;

  factory EventHistoryEntry.fromJson(Map<String, dynamic> json) =>
      _$EventHistoryEntryFromJson(json);

  HistoryKind get kindEnum => HistoryKind.fromRaw(kind);

  /// Poll question (for poll_* kinds), pulled from the detail blob.
  String? get pollQuestion => detail['question'] as String?;

  /// Outcome string for poll_closed: 'winner' | 'tie' | 'no_votes'.
  String? get pollOutcome => detail['outcome'] as String?;

  /// Winning option label for poll_closed (when outcome == 'winner').
  String? get pollWinnerLabel => detail['winner_label'] as String?;
}
