/// EventDetailRepository — members & RSVP for one event. RLS gates everything:
/// reads return only what a member may see; writes are rejected unless the
/// caller is an organizer (or acting on their own row). No client visibility
/// logic. Adding a group/crew is delegated to the Group/Crew repositories'
/// already-shipped assign_* RPCs (called from the controller), not duplicated.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'event_member.dart';

class EventDetailRepository {
  EventDetailRepository(this._client);
  final SupabaseClient _client;

  /// One-shot fetch of an event's members, joined to their profiles, organizers
  /// first then by handle.
  Future<List<EventMember>> fetchMembers(String eventId) async {
    try {
      final rows = await _client
          .from('event_members')
          .select('user_id, role, rsvp, '
              'profile:profiles!event_members_user_id_fkey(*)')
          .eq('event_id', eventId);
      final members = rows.map(EventMember.fromJson).toList()
        ..sort((a, b) {
          if (a.isOrganizer != b.isOrganizer) return a.isOrganizer ? -1 : 1;
          return (a.profile.handle ?? '')
              .toLowerCase()
              .compareTo((b.profile.handle ?? '').toLowerCase());
        });
      return members;
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Live member list: re-fetch the joined rows whenever event_members changes
  /// for this event.
  Stream<List<EventMember>> watchMembers(String eventId) {
    return _client
        .from('event_members')
        .stream(primaryKey: ['event_id', 'user_id'])
        .eq('event_id', eventId)
        .asyncMap((_) => fetchMembers(eventId));
  }

  /// Set the caller's own RSVP (RLS allows a member to update their own row).
  Future<void> setMyRsvp(String eventId, RsvpStatus rsvp) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      await _client
          .from('event_members')
          .update({'rsvp': rsvp.name})
          .eq('event_id', eventId)
          .eq('user_id', uid);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Add a friend as a member (organizer-only AND must be your friend — RLS
  /// enforces both; we surface PermissionFailure otherwise).
  Future<void> addMember(String eventId, String userId) async {
    final uid = _client.auth.currentUser?.id;
    try {
      await _client.from('event_members').insert({
        'event_id': eventId,
        'user_id': userId,
        'added_by': uid,
      });
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Remove a member (organizer removes anyone; a member removes themselves).
  Future<void> removeMember(String eventId, String userId) async {
    try {
      await _client
          .from('event_members')
          .delete()
          .eq('event_id', eventId)
          .eq('user_id', userId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Per-member "has a scheduling conflict elsewhere" flags for this event's
  /// roster, in one round-trip. BOOLEAN ONLY — the RPC never returns which
  /// other event is conflicting, so this can never leak an event a third
  /// party (the caller, viewing someone else's card) isn't allowed to see.
  Future<Map<String, bool>> fetchMemberConflicts(String eventId) async {
    try {
      final rows = await _client
          .rpc('event_member_conflicts', params: {'p_event': eventId});
      return {
        for (final r in (rows as List))
          (r as Map)['user_id'] as String: r['has_conflict'] as bool,
      };
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// The CALLER's own other events that overlap this one (by title). Always
  /// safe to show in full: the caller is, by definition, a member of every
  /// event returned here.
  Future<List<({String id, String title})>> fetchMyConflicts(
      String eventId) async {
    try {
      final rows =
          await _client.rpc('my_conflicting_events', params: {'p_event': eventId});
      return [
        for (final r in (rows as List))
          (id: (r as Map)['id'] as String, title: r['title'] as String),
      ];
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final eventDetailRepositoryProvider = Provider<EventDetailRepository>((ref) {
  return EventDetailRepository(ref.watch(supabaseClientProvider));
});
