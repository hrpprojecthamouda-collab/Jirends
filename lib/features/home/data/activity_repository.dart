/// ActivityRepository — builds the Home feed from data the user can ALREADY
/// see. It queries recent comments and recent items across the user's visible
/// events; every row is RLS-scoped, so the feed can never name or hint at an
/// event the user isn't a member of.
///
/// CARDINAL RULE: this is a derived view, not a new visibility path. We add no
/// filters and no joins that could surface a hidden event — a surprise the user
/// is the target of simply has no comments/items visible to them, so it never
/// appears here. Do not "enrich" this with anything outside the member-scoped
/// tables.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'activity_item.dart';

class ActivityRepository {
  ActivityRepository(this._client);
  final SupabaseClient _client;

  /// The most recent activity (comments + items) across the user's visible
  /// events, newest first, capped at [limit].
  Future<List<ActivityItem>> fetchRecent({int limit = 30}) async {
    try {
      final commentRows = await _client
          .from('comments')
          .select('id, created_at, body, '
              'author:profiles!comments_author_id_fkey(nickname, tagline), '
              'event:events!comments_event_id_fkey(id, title)')
          .order('created_at', ascending: false)
          .limit(limit);

      final itemRows = await _client
          .from('event_items')
          .select('id, created_at, title, '
              'event:events!event_items_event_id_fkey(id, title)')
          .order('created_at', ascending: false)
          .limit(limit);

      final items = <ActivityItem>[
        for (final r in commentRows) ActivityItem.fromCommentRow(r),
        for (final r in itemRows) ActivityItem.fromItemRow(r),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return items.take(limit).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return ActivityRepository(ref.watch(supabaseClientProvider));
});
