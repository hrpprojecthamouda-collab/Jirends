/// GroupRepository — Type-1 selection groups (friend_groups). Owner-private:
/// every query is scoped to the caller by RLS. Members are the caller's friends,
/// rendered as [Profile]. A group is never a permission; `assignGroupToEvent`
/// expands it into individual event_members rows via the SECURITY DEFINER RPC.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../auth/data/profile.dart';
import 'friend_group.dart';

class GroupRepository {
  GroupRepository(this._client);
  final SupabaseClient _client;

  /// Stream of the caller's selection groups (RLS scopes to owner).
  Stream<List<FriendGroup>> watchGroups() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return Stream.value(const []);
    return _client
        .from('friend_groups')
        .stream(primaryKey: ['id'])
        .eq('owner_id', uid)
        .map((rows) {
          final groups = rows.map(FriendGroup.fromJson).toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return groups;
        });
  }

  Future<FriendGroup> createGroup(String name) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      final row = await _client
          .from('friend_groups')
          .insert({'owner_id': uid, 'name': name.trim()})
          .select()
          .single();
      return FriendGroup.fromJson(row);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> renameGroup(String groupId, String name) async {
    try {
      await _client
          .from('friend_groups')
          .update({'name': name.trim()}).eq('id', groupId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> deleteGroup(String groupId) async {
    try {
      await _client.from('friend_groups').delete().eq('id', groupId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// The friends currently in a group, as profiles (joined via the FK).
  Future<List<Profile>> fetchMembers(String groupId) async {
    try {
      final rows = await _client
          .from('friend_group_members')
          .select('friend:profiles!friend_group_members_friend_id_fkey(*)')
          .eq('group_id', groupId);
      final profiles = rows
          .map((r) => Profile.fromJson(r['friend'] as Map<String, dynamic>))
          .toList()
        ..sort((a, b) =>
            (a.handle ?? '').toLowerCase().compareTo((b.handle ?? '').toLowerCase()));
      return profiles;
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> addMember(String groupId, String friendId) async {
    try {
      await _client
          .from('friend_group_members')
          .insert({'group_id': groupId, 'friend_id': friendId});
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> removeMember(String groupId, String friendId) async {
    try {
      await _client
          .from('friend_group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('friend_id', friendId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Expand the group's CURRENT friends into the event as members (one-time
  /// snapshot). Returns how many were added. Used by the event-detail slice.
  Future<int> assignGroupToEvent(String groupId, String eventId) async {
    try {
      final added = await _client.rpc('assign_group_to_event',
          params: {'p_group': groupId, 'p_event': eventId});
      return (added as num).toInt();
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(ref.watch(supabaseClientProvider));
});
