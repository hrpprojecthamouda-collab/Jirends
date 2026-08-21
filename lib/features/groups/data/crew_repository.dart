/// CrewRepository — Type-2 shared, visible groups (crews). RLS returns crews you
/// OWN or BELONG TO; the roster is readable by every member. Only the owner may
/// write (create/rename/delete, add/remove members). A crew is never a
/// permission; `assignCrewToEvent` expands it into event_members via the
/// SECURITY DEFINER RPC.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../auth/data/profile.dart';
import 'crew.dart';

class CrewRepository {
  CrewRepository(this._client);
  final SupabaseClient _client;

  /// Stream of crews the caller can see (owned OR a member of). RLS decides
  /// which; we don't filter client-side. The crews stream carries only crew
  /// rows, so we map them straight to models.
  Stream<List<Crew>> watchCrews() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return Stream.value(const []);
    return _client.from('crews').stream(primaryKey: ['id']).map((rows) {
      final crews = rows.map(Crew.fromJson).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return crews;
    });
  }

  /// One-shot list of the crews the caller can see, alphabetised.
  ///
  /// Pickers want a snapshot, not a subscription — see loadForPicker. RLS
  /// scopes the rows, so there is no owner filter here (crews are shared).
  Future<List<Crew>> fetchCrews() async {
    if (_client.auth.currentUser?.id == null) return const [];
    try {
      final rows = await _client.from('crews').select();
      return rows.map(Crew.fromJson).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<Crew> createCrew(String name) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      final row = await _client
          .from('crews')
          .insert({'owner_id': uid, 'name': name.trim()})
          .select()
          .single();
      return Crew.fromJson(row);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> renameCrew(String crewId, String name) async {
    try {
      await _client.from('crews').update({'name': name.trim()}).eq('id', crewId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> deleteCrew(String crewId) async {
    try {
      await _client.from('crews').delete().eq('id', crewId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// The crew's members as profiles (joined via the FK). Readable by any member.
  Future<List<Profile>> fetchMembers(String crewId) async {
    try {
      final rows = await _client
          .from('crew_members')
          .select('member:profiles!crew_members_user_id_fkey(*)')
          .eq('crew_id', crewId);
      final profiles = rows
          .map((r) => Profile.fromJson(r['member'] as Map<String, dynamic>))
          .toList()
        ..sort((a, b) =>
            (a.handle ?? '').toLowerCase().compareTo((b.handle ?? '').toLowerCase()));
      return profiles;
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Add a member (owner only — RLS enforces). `userId` is any profile id; crews
  /// do not require friendship (unlike groups).
  Future<void> addMember(String crewId, String userId) async {
    final uid = _client.auth.currentUser?.id;
    try {
      await _client.from('crew_members').insert({
        'crew_id': crewId,
        'user_id': userId,
        'added_by': uid,
      });
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> removeMember(String crewId, String userId) async {
    try {
      await _client
          .from('crew_members')
          .delete()
          .eq('crew_id', crewId)
          .eq('user_id', userId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Expand the crew's CURRENT members into the event (one-time snapshot).
  /// Returns how many were added. Used by the event-detail slice.
  Future<int> assignCrewToEvent(String crewId, String eventId) async {
    try {
      final added = await _client.rpc('assign_crew_to_event',
          params: {'p_crew': crewId, 'p_event': eventId});
      return (added as num).toInt();
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final crewRepositoryProvider = Provider<CrewRepository>((ref) {
  return CrewRepository(ref.watch(supabaseClientProvider));
});
