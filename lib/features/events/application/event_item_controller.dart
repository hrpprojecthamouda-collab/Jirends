/// Event item (sub-task) controllers: a live list per event plus an action
/// notifier for add / toggle done / assign-claim / delete.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/event_item.dart';
import '../data/event_item_repository.dart';

final eventItemsProvider =
    StreamProvider.family<List<EventItem>, String>((ref, eventId) {
  return ref.watch(eventItemRepositoryProvider).watchItems(eventId);
});

class ItemActionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  EventItemRepository get _repo => ref.read(eventItemRepositoryProvider);

  Future<bool> add(String eventId, String title) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.addItem(eventId, title));
    return !state.hasError;
  }

  Future<void> setDone(String itemId, bool isDone) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.setDone(itemId, isDone));
  }

  Future<void> assign(String itemId, String? userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.assign(itemId, userId));
  }

  Future<void> claim(String itemId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.claim(itemId));
  }

  Future<void> delete(String itemId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.deleteItem(itemId));
  }
}

final itemActionsControllerProvider =
    AsyncNotifierProvider<ItemActionsController, void>(ItemActionsController.new);
