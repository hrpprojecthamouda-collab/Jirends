/// Notifications controller. `myNotificationsProvider` streams the caller's
/// own notifications (re-fetches the joined rows whenever they change);
/// `unreadCountProvider` derives just the count so the bell badge doesn't
/// rebuild on every list change. `NotificationActionsController` holds the
/// mark-all-read action.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/notification.dart';
import '../data/notification_repository.dart';

/// The caller's notifications as a live `AsyncValue<List<AppNotification>>`.
final myNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  ref.watch(currentSessionProvider); // re-subscribe on sign in/out
  return ref.watch(notificationRepositoryProvider).watchNotifications();
});

/// Just the unread count, derived from the same stream — the bell badge binds
/// to this instead of the full list so it doesn't rebuild on every change.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(myNotificationsProvider).value ?? const [];
  return notifications.where((n) => n.isUnread).length;
});

class NotificationActionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  NotificationRepository get _repo => ref.read(notificationRepositoryProvider);

  Future<void> markAllRead() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.markAllRead);
  }
}

final notificationActionsControllerProvider =
    AsyncNotifierProvider<NotificationActionsController, void>(
        NotificationActionsController.new);
