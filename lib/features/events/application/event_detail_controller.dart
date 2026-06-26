/// Event-detail controllers: members (live), the type's phases, and an action
/// notifier for RSVP / add member / add group / add crew / remove. Adding a
/// group or crew reuses the existing Group/Crew repositories' assign_* RPCs.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../groups/data/crew_repository.dart';
import '../../groups/data/group_repository.dart';
import '../data/event.dart';
import '../data/event_detail_repository.dart';
import '../data/event_member.dart';
import '../data/event_phase.dart';
import '../data/event_type_repository.dart';

/// Live members of one event.
final eventMembersProvider =
    StreamProvider.family<List<EventMember>, String>((ref, eventId) {
  return ref.watch(eventDetailRepositoryProvider).watchMembers(eventId);
});

/// The ordered workflow phases for an event type (config; cached per type).
final eventPhasesProvider =
    FutureProvider.family<List<EventPhase>, EventType>((ref, type) {
  return ref.watch(eventTypeRepositoryProvider).fetchPhases(type);
});

/// Per-member "has a scheduling conflict elsewhere" flags for this event's
/// roster (boolean only — see EventDetailRepository.fetchMemberConflicts).
/// One-shot, like eventPollsProvider: invalidated explicitly after any
/// member-add action so the flags reflect the new roster.
final memberConflictsProvider =
    FutureProvider.family<Map<String, bool>, String>((ref, eventId) {
  return ref.watch(eventDetailRepositoryProvider).fetchMemberConflicts(eventId);
});

/// The CALLER's own other events that overlap this one (titles — always safe,
/// see EventDetailRepository.fetchMyConflicts).
final myConflictsProvider =
    FutureProvider.family<List<({String id, String title})>, String>(
        (ref, eventId) {
  return ref.watch(eventDetailRepositoryProvider).fetchMyConflicts(eventId);
});

class MemberActionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  EventDetailRepository get _repo => ref.read(eventDetailRepositoryProvider);

  Future<void> setMyRsvp(String eventId, RsvpStatus rsvp) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.setMyRsvp(eventId, rsvp));
  }

  Future<void> addMember(String eventId, String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.addMember(eventId, userId));
    if (!state.hasError) ref.invalidate(memberConflictsProvider(eventId));
  }

  Future<void> removeMember(String eventId, String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.removeMember(eventId, userId));
  }

  /// Expand a selection group onto the event. Returns the count added (null on
  /// error — surfaced via [state]).
  Future<int?> addGroup(String eventId, String groupId) async {
    state = const AsyncLoading();
    int? added;
    state = await AsyncValue.guard(() async {
      added = await ref
          .read(groupRepositoryProvider)
          .assignGroupToEvent(groupId, eventId);
    });
    if (!state.hasError) ref.invalidate(memberConflictsProvider(eventId));
    return state.hasError ? null : added;
  }

  /// Expand a crew onto the event. Returns the count added.
  Future<int?> addCrew(String eventId, String crewId) async {
    state = const AsyncLoading();
    int? added;
    state = await AsyncValue.guard(() async {
      added = await ref
          .read(crewRepositoryProvider)
          .assignCrewToEvent(crewId, eventId);
    });
    if (!state.hasError) ref.invalidate(memberConflictsProvider(eventId));
    return state.hasError ? null : added;
  }
}

final memberActionsControllerProvider =
    AsyncNotifierProvider<MemberActionsController, void>(
        MemberActionsController.new);
