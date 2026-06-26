/// Notification bottom sheet — lists the caller's notifications (newest
/// first), one icon+message+time row per kind. Opening the sheet marks
/// everything read. Read-only: no per-item actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/util/short_time.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/notification_controller.dart';
import '../../data/notification.dart';

Future<void> showNotificationSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => const _NotificationSheet(),
  );
}

class _NotificationSheet extends ConsumerStatefulWidget {
  const _NotificationSheet();

  @override
  ConsumerState<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends ConsumerState<_NotificationSheet> {
  @override
  void initState() {
    super.initState();
    // Mark everything read once the sheet is actually shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationActionsControllerProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final notificationsAsync = ref.watch(myNotificationsProvider);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(t.notificationsTitle,
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            const Divider(height: 1),
            Expanded(
              child: notificationsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(messageForError(e))),
                data: (notifications) => notifications.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(t.notificationsEmpty,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.inkMuted)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: notifications.length,
                        itemBuilder: (context, i) =>
                            _NotificationTile(notification: notifications[i]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});
  final AppNotification notification;

  (IconData, Color) _iconFor(NotificationKind k) => switch (k) {
        NotificationKind.friendAdded => (Icons.person_add_alt_1, AppColors.primary),
        NotificationKind.crewAdded => (Icons.groups_outlined, AppColors.violet),
        NotificationKind.eventMemberAdded => (Icons.event_available, AppColors.blue),
        NotificationKind.eventConfirmed => (Icons.check_circle_outline, AppColors.teal),
        NotificationKind.eventCancelled => (Icons.cancel_outlined, AppColors.coral),
        NotificationKind.other => (Icons.notifications_outlined, AppColors.inkMuted),
      };

  String _messageFor(AppLocalizations t, AppNotification n) {
    final who = n.actor?.handle ?? '…';
    return switch (n.kindEnum) {
      NotificationKind.friendAdded => t.notificationFriendAdded(who),
      NotificationKind.crewAdded => t.notificationCrewAdded(who, n.crew?.name ?? ''),
      NotificationKind.eventMemberAdded =>
        t.notificationEventMemberAdded(who, n.event?.title ?? ''),
      NotificationKind.eventCancelled =>
        t.notificationEventCancelled(n.event?.title ?? ''),
      NotificationKind.eventConfirmed =>
        t.notificationEventConfirmed(n.event?.title ?? ''),
      NotificationKind.other => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (icon, color) = _iconFor(notification.kindEnum);
    final eventId = notification.eventId;

    return ListTile(
      leading: CircleAvatar(
        // ignore: deprecated_member_use
        backgroundColor: color.withOpacity(0.18),
        foregroundColor: color,
        child: Icon(icon, size: 20),
      ),
      title: Text(_messageFor(t, notification)),
      subtitle: Text(formatShortTime(notification.createdAt.toLocal()),
          style: const TextStyle(color: AppColors.inkMuted)),
      onTap: eventId == null
          ? null
          : () {
              Navigator.of(context).pop();
              context.push(AppRoutes.eventDetail(eventId));
            },
    );
  }
}
