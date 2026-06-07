/// Status workflow controller — advance an event to another phase. Organizer-
/// only (RLS) and the phase must belong to the type (composite FK); both
/// surface as failures the UI shows. Invalidates the event so the header
/// reflects the new phase.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/event_repository.dart';
import 'event_list_controller.dart';

class EventStatusController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> advance(String eventId, String phaseKey) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(eventRepositoryProvider).advanceStatus(eventId, phaseKey));
    // Refresh the single-event view so the header shows the new status.
    ref.invalidate(eventByIdProvider(eventId));
  }
}

final eventStatusControllerProvider =
    AsyncNotifierProvider<EventStatusController, void>(
        EventStatusController.new);
