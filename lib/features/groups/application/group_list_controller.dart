/// Type-1 selection group controllers: a live list of the caller's groups, a
/// family provider for one group's members, and an action notifier for
/// create/rename/delete and member add/remove.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/data/profile.dart';
import '../data/friend_group.dart';
import '../data/group_repository.dart';

/// The caller's selection groups as a live `AsyncValue<List<FriendGroup>>`.
final groupListProvider = StreamProvider<List<FriendGroup>>((ref) {
  ref.watch(currentSessionProvider);
  return ref.watch(groupRepositoryProvider).watchGroups();
});

/// The members (profiles) of one group. Re-read after a member change by
/// invalidating this family entry.
final groupMembersProvider =
    FutureProvider.family<List<Profile>, String>((ref, groupId) {
  return ref.watch(groupRepositoryProvider).fetchMembers(groupId);
});

class GroupActionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  GroupRepository get _repo => ref.read(groupRepositoryProvider);

  Future<bool> create(String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.createGroup(name));
    return !state.hasError;
  }

  Future<void> rename(String groupId, String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.renameGroup(groupId, name));
  }

  Future<void> delete(String groupId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.deleteGroup(groupId));
  }

  Future<void> addMember(String groupId, String friendId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.addMember(groupId, friendId));
    ref.invalidate(groupMembersProvider(groupId));
  }

  Future<void> removeMember(String groupId, String friendId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.removeMember(groupId, friendId));
    ref.invalidate(groupMembersProvider(groupId));
  }
}

final groupActionsControllerProvider =
    AsyncNotifierProvider<GroupActionsController, void>(
        GroupActionsController.new);
