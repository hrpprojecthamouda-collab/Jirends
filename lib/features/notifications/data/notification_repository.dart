/// NotificationRepository — the caller's own notifications, joined to the
/// actor profile and the related event title / crew name. RLS scopes every
/// read to recipient_id = auth.uid(); there is no client write path beyond
/// marking your own rows read (the DB triggers do all the writing).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'notification.dart';

class NotificationRepository {
  NotificationRepository(this._client);
  final SupabaseClient _client;

  /// The caller's notifications, newest first.
  Future<List<AppNotification>> fetchNotifications() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await _client
          .from('notifications')
          .select('*, '
              'actor:profiles!notifications_actor_id_fkey(*), '
              'event:events!notifications_event_id_fkey(id,title), '
              'crew:crews!notifications_crew_id_fkey(id,name)')
          .eq('recipient_id', uid)
          .order('created_at', ascending: false);
      return rows.map(AppNotification.fromJson).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Live notifications — re-fetch the joined rows on any change to the
  /// caller's own notifications.
  Stream<List<AppNotification>> watchNotifications() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return Stream.value(const []);
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('recipient_id', uid)
        .asyncMap((_) => fetchNotifications());
  }

  /// Mark all of the caller's unread notifications read in one call.
  Future<void> markAllRead() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('recipient_id', uid)
          .filter('read_at', 'is', null);
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(supabaseClientProvider));
});
