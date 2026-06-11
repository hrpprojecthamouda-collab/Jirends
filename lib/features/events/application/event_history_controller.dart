/// Live event-history provider — the change log for one event (newest first).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/event_history_entry.dart';
import '../data/event_history_repository.dart';

/// autoDispose: tears down the realtime channel when the History tab leaves
/// the tree instead of keeping one alive per visited event for the session.
final eventHistoryProvider = StreamProvider.autoDispose
    .family<List<EventHistoryEntry>, String>((ref, eventId) {
  return ref.watch(eventHistoryRepositoryProvider).watchHistory(eventId);
});
