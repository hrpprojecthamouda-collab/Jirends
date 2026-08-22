/// Event list + create controllers.
///
/// `eventListProvider` streams the user's visible events (realtime). It is a
/// plain StreamProvider because the list is read-only state; the create action
/// lives in [CreateEventController]. The stream re-subscribes when the session
/// changes so signing in/out swaps the data.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/event.dart';
import '../data/event_repository.dart';

/// The signed-in user's visible events, as a live `AsyncValue<List<Event>>`.
final eventListProvider = StreamProvider<List<Event>>((ref) {
  // Re-run whenever the session changes (sign in/out re-subscribes).
  ref.watch(currentSessionProvider);
  return ref.watch(eventRepositoryProvider).watchMyEvents();
});

/// Attendee count per event id, for the list cards. Live, so a card's count
/// follows people joining or leaving without a refresh.
final eventMemberCountsProvider = StreamProvider<Map<String, int>>((ref) {
  ref.watch(currentSessionProvider);
  return ref.watch(eventRepositoryProvider).watchMemberCounts();
});

/// A single event by id, for the detail screen. Returns null when the event
/// doesn't exist or isn't visible (RLS) — the UI shows the same "not found"
/// either way, by design.
final eventByIdProvider =
    FutureProvider.family<Event?, String>((ref, id) async {
  return ref.watch(eventRepositoryProvider).fetchEvent(id);
});

/// Action controller for creating an event. Exposes an AsyncValue the create
/// screen binds to for loading/error; returns the new id on success so the UI
/// can navigate to it (or pop).
class CreateEventController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Action-oriented; no initial work.
  }

  EventRepository get _repo => ref.read(eventRepositoryProvider);

  /// Returns the created event's id, or null if it failed (error is in [state]).
  Future<String?> create({
    required String title,
    required EventType eventType,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
    String? location,
  }) async {
    state = const AsyncLoading();
    String? id;
    state = await AsyncValue.guard(() async {
      final event = await _repo.createEvent(
        title: title,
        eventType: eventType,
        description: description,
        startsAt: startsAt,
        endsAt: endsAt,
        location: location,
      );
      id = event.id;
    });
    return state.hasError ? null : id;
  }
}

final createEventControllerProvider =
    AsyncNotifierProvider<CreateEventController, void>(CreateEventController.new);

/// Action controller for editing an existing event's core fields (organizer
/// only — RLS enforces). Invalidates the single-event view on success so the
/// detail header refreshes; the list updates live via realtime.
class EditEventController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> save(
    String eventId, {
    String? title,
    String? description,
    bool clearDescription = false,
    DateTime? startsAt,
    bool clearStartsAt = false,
    DateTime? endsAt,
    bool clearEndsAt = false,
    String? location,
    bool clearLocation = false,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(eventRepositoryProvider).updateEvent(
          eventId,
          title: title,
          description: description,
          clearDescription: clearDescription,
          startsAt: startsAt,
          clearStartsAt: clearStartsAt,
          endsAt: endsAt,
          clearEndsAt: clearEndsAt,
          location: location,
          clearLocation: clearLocation,
        ));
    if (!state.hasError) ref.invalidate(eventByIdProvider(eventId));
    return !state.hasError;
  }

  /// Delete the event (organizer only — RLS enforces). Returns true on success;
  /// the caller pops back to the list, which updates live via realtime.
  Future<bool> delete(String eventId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(eventRepositoryProvider).deleteEvent(eventId));
    return !state.hasError;
  }
}

final editEventControllerProvider =
    AsyncNotifierProvider<EditEventController, void>(EditEventController.new);
