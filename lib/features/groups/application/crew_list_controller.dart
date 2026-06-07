/// Type-2 crew controllers: a live list of crews the caller can see (owned or a
/// member of), a family provider for one crew's roster, and an action notifier
/// for create/rename/delete and member add/remove (owner-only; RLS enforces).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/data/profile.dart';
import '../data/crew.dart';
import '../data/crew_repository.dart';

/// Crews the caller can see as a live `AsyncValue<List<Crew>>`.
final crewListProvider = StreamProvider<List<Crew>>((ref) {
  ref.watch(currentSessionProvider);
  return ref.watch(crewRepositoryProvider).watchCrews();
});

/// The roster (profiles) of one crew. Invalidate to re-read after a change.
final crewMembersProvider =
    FutureProvider.family<List<Profile>, String>((ref, crewId) {
  return ref.watch(crewRepositoryProvider).fetchMembers(crewId);
});

class CrewActionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  CrewRepository get _repo => ref.read(crewRepositoryProvider);

  Future<bool> create(String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.createCrew(name));
    return !state.hasError;
  }

  Future<void> rename(String crewId, String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.renameCrew(crewId, name));
  }

  Future<void> delete(String crewId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.deleteCrew(crewId));
  }

  Future<void> addMember(String crewId, String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.addMember(crewId, userId));
    ref.invalidate(crewMembersProvider(crewId));
  }

  Future<void> removeMember(String crewId, String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.removeMember(crewId, userId));
    ref.invalidate(crewMembersProvider(crewId));
  }
}

final crewActionsControllerProvider =
    AsyncNotifierProvider<CrewActionsController, void>(CrewActionsController.new);
