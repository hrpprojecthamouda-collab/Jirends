/// EventRepository — the only layer that talks to Supabase about events.
/// Returns [Event] domain models, throws typed [Failure]s.
///
/// THE CARDINAL RULE lives here by NOT being here: none of these methods filter
/// for visibility. `from('events').select()` returns only the rows RLS allows
/// (events the user is a member of, or created). A surprise the user is the
/// target of simply never comes back. Do not add a client-side visibility
/// filter — that would be a bug, not a feature.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'event.dart';

class EventRepository {
  EventRepository(this._client);
  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('events');

  /// One-shot fetch of the events visible to the signed-in user, newest first.
  Future<List<Event>> fetchMyEvents() async {
    try {
      final rows = await _table.select().order('created_at', ascending: false);
      return rows.map(Event.fromJson).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Realtime stream of the user's visible events. RLS applies to realtime too,
  /// so the stream only ever carries rows the user may see. Sorted newest-first
  /// in Dart because `.stream()` cannot be combined with a server-side order
  /// the way `.select()` can.
  Stream<List<Event>> watchMyEvents() {
    return _table.stream(primaryKey: ['id']).map((rows) {
      final events = rows.map(Event.fromJson).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return events;
    });
  }

  /// Advance (or set) an event's status to a phase KEY. Organizer-only by RLS;
  /// the composite FK (event_type, status) -> event_type_phases validates that
  /// the phase belongs to the type, so an invalid key surfaces as a
  /// PermissionFailure via mapToFailure.
  Future<void> advanceStatus(String eventId, String phaseKey) async {
    try {
      await _table.update({'status': phaseKey}).eq('id', eventId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Fetch a single event by id. Returns null if it doesn't exist OR isn't
  /// visible to the user — by design we cannot (and must not) distinguish the
  /// two. `.maybeSingle()` gives null rather than throwing on zero rows.
  Future<Event?> fetchEvent(String id) async {
    try {
      final row = await _table.select().eq('id', id).maybeSingle();
      return row == null ? null : Event.fromJson(row);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Create an event as the signed-in user. `status` is left unset so the DB
  /// trigger starts it at the type's first phase; the creator is auto-added as
  /// organizer by an AFTER-INSERT trigger. Returns the created [Event].
  Future<Event> createEvent({
    required String title,
    required EventType eventType,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
    String? location,
    /// The friend this event is hidden from (a surprise). The DB enforces the
    /// guards: the target is never added as a member and can never read it.
    String? surpriseTarget,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      final row = await _table
          .insert({
            'title': title,
            'event_type': eventType.name,
            'created_by': uid,
            if (description != null && description.isNotEmpty)
              'description': description,
            if (startsAt != null) 'starts_at': startsAt.toUtc().toIso8601String(),
            if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
            if (location != null && location.isNotEmpty) 'location': location,
            'surprise_target': ?surpriseTarget,
          })
          .select()
          .single();
      return Event.fromJson(row);
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(ref.watch(supabaseClientProvider));
});
