/// EventHistoryRepository — the read-only change log for one event, joined to
/// each entry's actor profile. RLS scopes reads to members; there is no write
/// path (the DB logs entries itself). No client visibility logic.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'event_history_entry.dart';

class EventHistoryRepository {
  EventHistoryRepository(this._client);
  final SupabaseClient _client;

  /// History for the event, newest first, joined to the actor profile.
  Future<List<EventHistoryEntry>> fetchHistory(String eventId) async {
    try {
      final rows = await _client
          .from('event_history')
          .select('*, actor:profiles!event_history_actor_id_fkey(*)')
          .eq('event_id', eventId)
          .order('created_at', ascending: false);
      return rows.map(EventHistoryEntry.fromJson).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Live history — re-fetch the joined rows on any change to the event's log.
  Stream<List<EventHistoryEntry>> watchHistory(String eventId) {
    return _client
        .from('event_history')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .asyncMap((_) => fetchHistory(eventId));
  }
}

final eventHistoryRepositoryProvider = Provider<EventHistoryRepository>((ref) {
  return EventHistoryRepository(ref.watch(supabaseClientProvider));
});
