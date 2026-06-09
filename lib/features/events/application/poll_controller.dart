/// Poll controllers: a live list of composed poll views per event, plus an
/// action notifier for create / vote / close / reopen / delete.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/poll.dart';
import '../data/poll_repository.dart';

final eventPollsProvider =
    StreamProvider.family<List<PollView>, String>((ref, eventId) {
  return ref.watch(pollRepositoryProvider).watchPolls(eventId);
});

class PollActionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  PollRepository get _repo => ref.read(pollRepositoryProvider);

  Future<bool> create(
    String eventId, {
    required String question,
    required PollKind kind,
    required PollMode mode,
    required List<String> labels,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.createPoll(
          eventId,
          question: question,
          kind: kind,
          mode: mode,
          labels: labels,
        ));
    return !state.hasError;
  }

  Future<void> vote(String pollId, String eventId, String optionId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.vote(pollId, eventId, optionId));
  }

  Future<void> close(String pollId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.closePoll(pollId));
  }

  Future<void> reopen(String pollId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.reopenPoll(pollId));
  }

  Future<void> delete(String pollId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.deletePoll(pollId));
  }
}

final pollActionsControllerProvider =
    AsyncNotifierProvider<PollActionsController, void>(PollActionsController.new);
