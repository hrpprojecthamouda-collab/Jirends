/// Live event-history provider — the change log for one event (newest first).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/event_history_entry.dart';
import '../data/event_history_repository.dart';

final eventHistoryProvider =
    StreamProvider.family<List<EventHistoryEntry>, String>((ref, eventId) {
  return ref.watch(eventHistoryRepositoryProvider).watchHistory(eventId);
});
