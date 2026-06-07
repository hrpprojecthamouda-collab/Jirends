/// EventItem — a row of public.event_items: an assignable sub-task on an event
/// ("who brings dessert"). Joined to the assignee's profile when one is set.
/// Scoped to event members by RLS; no client visibility logic.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/data/profile.dart';

part 'event_item.freezed.dart';
part 'event_item.g.dart';

@freezed
abstract class EventItem with _$EventItem {
  const EventItem._();

  const factory EventItem({
    required String id,
    required String eventId,
    required String title,
    required bool isDone,
    String? assignedTo,
    required int position,
    required String createdBy,
    /// The assignee's profile, present only when assignedTo is set.
    Profile? assignee,
  }) = _EventItem;

  factory EventItem.fromJson(Map<String, dynamic> json) =>
      _$EventItemFromJson(json);

  bool get isAssigned => assignedTo != null;
}
