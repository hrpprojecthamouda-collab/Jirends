/// Notification bottom sheet — lists the caller's notifications (newest
/// first), one icon+message+time row per kind.
///
/// Opening the sheet marks everything read, which is why the unread rows are
/// highlighted from a SNAPSHOT taken the moment it opened rather than from
/// `isUnread`. Reading the live flag would highlight nothing: the update lands
/// before the first frame is on screen, so "what's new" would be invisible at
/// exactly the moment the user came to look for it.
///
/// Read-only otherwise: no per-item actions.
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
  /// Which notifications were unread when this sheet opened. Fixed for the
  /// lifetime of the sheet, so marking them read does not erase the highlight
  /// out from under the reader.
  Set<String> _newOnOpen = const {};
  bool _captured = false;

  /// Take the snapshot, then mark read — in that order, or the update races
  /// the snapshot and nothing is ever highlighted.
  void _captureThenMarkRead(List<AppNotification> notifications) {
    if (_captured) return;
    _captured = true;
    setState(() {
      _newOnOpen = {
        for (final n in notifications)
          if (n.isUnread) n.id,
      };
    });
    if (_newOnOpen.isEmpty) return; // nothing to clear
    ref.read(notificationActionsControllerProvider.notifier).markAllRead();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    // The bell badge watches this provider on every top-level screen, so it is
    // normally already loaded when the sheet opens. The listener covers the
    // cold case (deep link, slow first load) where it is not.
    ref.listen(myNotificationsProvider, (_, next) {
      final list = next.value;
      if (list != null && !_captured) _captureThenMarkRead(list);
    });

    final notificationsAsync = ref.watch(myNotificationsProvider);
    final loaded = notificationsAsync.value;
    if (loaded != null && !_captured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _captureThenMarkRead(loaded);
      });
    }

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
                              style: TextStyle(color: AppColors.inkMuted)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: notifications.length,
                        itemBuilder: (context, i) => _NotificationTile(
                          notification: notifications[i],
                          isNew: _newOnOpen.contains(notifications[i].id),
                        ),
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
  const _NotificationTile({
    required this.notification,
    required this.isNew,
  });
  final AppNotification notification;

  /// Unread when the sheet opened — see [_NotificationSheetState]. NOT
  /// `notification.isUnread`, which is already false by the time this builds.
  final bool isNew;

  (IconData, Color) _iconFor(NotificationKind k) => switch (k) {
        NotificationKind.friendAdded => (Icons.person_add_alt_1, AppColors.primary),
        NotificationKind.eventMemberAdded => (Icons.event_available, AppColors.blue),
        NotificationKind.eventConfirmed => (Icons.check_circle_outline, AppColors.teal),
        NotificationKind.eventCancelled => (Icons.cancel_outlined, AppColors.coral),
        NotificationKind.expenseAdded =>
          (Icons.receipt_long_outlined, AppColors.yellow),
        NotificationKind.commentMention =>
          (Icons.alternate_email, AppColors.primary),
        NotificationKind.other => (Icons.notifications_outlined, AppColors.inkMuted),
      };

  String _messageFor(AppLocalizations t, AppNotification n) {
    final who = n.actor?.handle ?? '…';
    return switch (n.kindEnum) {
      NotificationKind.friendAdded => t.notificationFriendAdded(who),
      NotificationKind.eventMemberAdded =>
        t.notificationEventMemberAdded(who, n.event?.title ?? ''),
      NotificationKind.eventCancelled =>
        t.notificationEventCancelled(n.event?.title ?? ''),
      NotificationKind.eventConfirmed =>
        t.notificationEventConfirmed(n.event?.title ?? ''),
      NotificationKind.expenseAdded =>
        t.notificationExpenseAdded(who, n.event?.title ?? ''),
      NotificationKind.commentMention =>
        t.notificationCommentMention(who, n.event?.title ?? ''),
      NotificationKind.other => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (icon, color) = _iconFor(notification.kindEnum);
    final eventId = notification.eventId;

    return Container(
      // Three cues, not one: a tinted ground, a heavier message, and a dot.
      // Colour alone would exclude anyone who cannot distinguish it, and at
      // 7% alpha the tint is deliberately faint — it should mark the row, not
      // shout over the message on it.
      color: isNew ? AppColors.primary.withValues(alpha: .07) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.18),
          foregroundColor: color,
          child: Icon(icon, size: 20),
        ),
        title: Text(
          _messageFor(t, notification),
          style: isNew ? const TextStyle(fontWeight: FontWeight.w700) : null,
        ),
        subtitle: Text(formatShortTime(notification.createdAt.toLocal()),
            style: TextStyle(color: AppColors.inkMuted)),
        trailing: isNew
            ? Semantics(
                label: t.notificationUnread,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
        onTap: eventId == null
            ? null
            : () {
                Navigator.of(context).pop();
                context.push(AppRoutes.eventDetail(eventId));
              },
      ),
    );
  }
}
