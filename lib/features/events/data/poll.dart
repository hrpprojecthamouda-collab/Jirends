/// Poll model — mirrors public.polls. A poll belongs to an event; members vote
/// once each; the creator closes it. Resolution mode is majority or a
/// weighted-random "wheel" (drawn once server-side at close). Kind is general /
/// date / place (date & place are organizer-created). Scoped by RLS to event
/// members; no client visibility logic.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'poll.freezed.dart';
part 'poll.g.dart';

enum PollKind { general, date, place }

enum PollMode { majority, weightedRandom }

enum PollStatus { open, closed }

@freezed
abstract class Poll with _$Poll {
  const Poll._();

  const factory Poll({
    required String id,
    required String eventId,
    required String question,
    required PollKind kind,
    required PollMode mode,
    required PollStatus status,
    required String createdBy,
    DateTime? closedAt,
    String? winningOptionId,
    @Default(false) bool isTie,
  }) = _Poll;

  factory Poll.fromJson(Map<String, dynamic> json) => _$PollFromJson(json);

  bool get isOpen => status == PollStatus.open;
  bool get isClosed => status == PollStatus.closed;
}
