/// EventTypeRepository — reads the per-type workflow config (event_type_phases).
/// Config is read-only to users and stable, so we fetch once per type. The
/// client renders the workflow from these rows — it never hardcodes phases.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'event.dart';
import 'event_phase.dart';

class EventTypeRepository {
  EventTypeRepository(this._client);
  final SupabaseClient _client;

  /// The ordered phases for an event type, lowest position first.
  Future<List<EventPhase>> fetchPhases(EventType type) async {
    try {
      final rows = await _client
          .from('event_type_phases')
          .select('key, label, position, is_terminal')
          .eq('event_type', type.name)
          .order('position', ascending: true);
      return rows.map(EventPhase.fromJson).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final eventTypeRepositoryProvider = Provider<EventTypeRepository>((ref) {
  return EventTypeRepository(ref.watch(supabaseClientProvider));
});
