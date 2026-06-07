/// Home activity feed provider. Re-fetches when the session changes. The feed
/// is RLS-scoped by construction (see ActivityRepository), so there is no
/// visibility logic here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/activity_item.dart';
import '../data/activity_repository.dart';

final activityFeedProvider = FutureProvider<List<ActivityItem>>((ref) async {
  ref.watch(currentSessionProvider);
  return ref.watch(activityRepositoryProvider).fetchRecent();
});
