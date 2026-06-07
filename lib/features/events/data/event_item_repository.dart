/// EventItemRepository — assignable sub-tasks for one event, joined to the
/// assignee's profile. RLS: members read; members add (created_by == self);
/// any member may tick/(re)assign; organizer or creator may delete. No client
/// visibility logic.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'event_item.dart';

class EventItemRepository {
  EventItemRepository(this._client);
  final SupabaseClient _client;

  Future<List<EventItem>> fetchItems(String eventId) async {
    try {
      final rows = await _client
          .from('event_items')
          .select('*, assignee:profiles!event_items_assigned_to_fkey(*)')
          .eq('event_id', eventId)
          .order('position', ascending: true)
          .order('created_at', ascending: true);
      return rows.map(EventItem.fromJson).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Stream<List<EventItem>> watchItems(String eventId) {
    return _client
        .from('event_items')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .asyncMap((_) => fetchItems(eventId));
  }

  Future<void> addItem(String eventId, String title) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      await _client.from('event_items').insert({
        'event_id': eventId,
        'title': title.trim(),
        'created_by': uid,
      });
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> setDone(String itemId, bool isDone) async {
    try {
      await _client.from('event_items').update({'is_done': isDone}).eq('id', itemId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Assign (or unassign with null) an item to a member.
  Future<void> assign(String itemId, String? userId) async {
    try {
      await _client
          .from('event_items')
          .update({'assigned_to': userId})
          .eq('id', itemId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Claim an item for the caller (assign to self).
  Future<void> claim(String itemId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    await assign(itemId, uid);
  }

  Future<void> deleteItem(String itemId) async {
    try {
      await _client.from('event_items').delete().eq('id', itemId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final eventItemRepositoryProvider = Provider<EventItemRepository>((ref) {
  return EventItemRepository(ref.watch(supabaseClientProvider));
});
