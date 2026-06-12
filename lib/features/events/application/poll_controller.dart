/// Poll controllers: a live list of composed poll views per event, plus an
/// action notifier for create / vote / close / reopen / delete.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/poll.dart';
import '../data/poll_repository.dart';
import 'event_list_controller.dart';

/// One-shot fetch of an event's composed poll views. A FutureProvider (not a
/// realtime stream): the polls list is built from several queries + RPCs, and a
/// realtime event on `polls` alone wouldn't reliably re-fire when only options
/// or votes change. The action controller invalidates this after every write so
/// the list refreshes deterministically.
final eventPollsProvider =
    FutureProvider.family<List<PollView>, String>((ref, eventId) {
  return ref.watch(pollRepositoryProvider).fetchPolls(eventId);
});

class PollActionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  PollRepository get _repo => ref.read(pollRepositoryProvider);

  /// Refresh the composed poll list for an event after a write.
  void _refresh(String eventId) => ref.invalidate(eventPollsProvider(eventId));

  Future<bool> create(
    String eventId, {
    required String question,
    required PollKind kind,
    required PollMode mode,
    required List<String> labels,
    List<String?>? values,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.createPoll(
          eventId,
          question: question,
          kind: kind,
          mode: mode,
          labels: labels,
          values: values,
        ));
    if (!state.hasError) _refresh(eventId);
    return !state.hasError;
  }

  Future<void> vote(String pollId, String eventId, String optionId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.vote(pollId, eventId, optionId));
    if (!state.hasError) _refresh(eventId);
  }

  Future<void> close(String pollId, String eventId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.closePoll(pollId));
    if (!state.hasError) {
      _refresh(eventId);
      // Closing a place/day/time poll applies the winner to the event server-
      // side — refresh it so the ticket header/Overview show the result.
      ref.invalidate(eventByIdProvider(eventId));
    }
  }

  Future<void> reopen(String pollId, String eventId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.reopenPoll(pollId));
    if (!state.hasError) _refresh(eventId);
  }

  Future<void> delete(String pollId, String eventId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.deletePoll(pollId));
    if (!state.hasError) _refresh(eventId);
  }
}

final pollActionsControllerProvider =
    AsyncNotifierProvider<PollActionsController, void>(PollActionsController.new);
