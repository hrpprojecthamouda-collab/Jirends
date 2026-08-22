/// Event model — mirrors public.events (the "ticket"). Visibility is the
/// database's job (the cardinal rule): if an Event reaches this layer at all,
/// the user is allowed to see it. Never filter Events for visibility in Dart.
///
/// `eventType` is one of the developer-defined types (trip/dinner/birthday/
/// meetup). `status` is a phase KEY belonging to that type — the DB validates
/// it and auto-sets the first phase on insert, so it is never null on a row we
/// read back.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'event.freezed.dart';
part 'event.g.dart';

/// The developer-defined event types (mirrors the `event_type` enum). The
/// per-type workflow phases and property fields live in DB config tables, not
/// here — this enum only names the types.
enum EventType {
  trip,
  dinner,
  birthday,
  meetup,
}

@freezed
abstract class Event with _$Event {
  const Event._();

  const factory Event({
    required String id,
    required String title,
    String? description,
    required EventType eventType,
    /// Phase key (e.g. 'idea', 'planning'). Non-null once the row exists.
    String? status,
    @Default(<String, dynamic>{}) Map<String, dynamic> properties,
    DateTime? startsAt,
    DateTime? endsAt,
    String? location,
    /// The user the event is hidden from. Null for normal events. The DB keeps
    /// the target out of event_members and refuses to add them — this field is
    /// purely informational for organizers who can see the event.
    required String createdBy,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Event;

  factory Event.fromJson(Map<String, dynamic> json) => _$EventFromJson(json);


  /// Only trips span a date RANGE (starts_at -> ends_at). Every other type
  /// happens at a single date+time (stored in starts_at; ends_at stays null).
  /// This is a UI/semantic rule — the DB columns are unchanged.
  bool get isTrip => eventType == EventType.trip;
}
