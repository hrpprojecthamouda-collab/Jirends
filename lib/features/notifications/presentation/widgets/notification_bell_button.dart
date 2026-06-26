/// NotificationBellButton — a bell icon with an unread-count badge, shown in
/// the AppBar actions of every top-level screen (mirrors ProfileAvatarButton's
/// reuse pattern). Tapping it opens a bottom sheet listing notifications and
/// marks them all read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/notification_controller.dart';
import 'notification_sheet.dart';

class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);

    return IconButton(
      tooltip: null,
      icon: Badge(
        label: Text('$unread'),
        isLabelVisible: unread > 0,
        backgroundColor: AppColors.coral,
        textColor: AppColors.onAccent,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => showNotificationSheet(context),
    );
  }
}
