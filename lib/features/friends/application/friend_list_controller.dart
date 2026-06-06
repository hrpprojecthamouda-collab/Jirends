/// Friends list + add/remove controllers.
///
/// `friendListProvider` streams the caller's address book (re-fetches the joined
/// profiles whenever the friends rows change). `FriendActionsController` holds
/// the add-by-handle and remove actions with an AsyncValue the UI binds to.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/data/profile.dart';
import '../data/friend_repository.dart';

/// The caller's friends as a live `AsyncValue<List<Profile>>`.
final friendListProvider = StreamProvider<List<Profile>>((ref) {
  ref.watch(currentSessionProvider); // re-subscribe on sign in/out
  return ref.watch(friendRepositoryProvider).watchFriends();
});

class FriendActionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  FriendRepository get _repo => ref.read(friendRepositoryProvider);

  /// Returns true on success (error otherwise lives in [state]).
  Future<bool> addByHandle(String handle) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.addByHandle(handle));
    return !state.hasError;
  }

  Future<void> remove(String friendId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.removeFriend(friendId));
  }
}

final friendActionsControllerProvider =
    AsyncNotifierProvider<FriendActionsController, void>(
        FriendActionsController.new);
