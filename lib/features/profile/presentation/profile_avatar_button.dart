/// ProfileAvatarButton — the little initials circle shown top-left in every main
/// screen's app bar. Tapping it opens the Profile screen (which holds Settings).
/// Reused across Home/Events/Friends/Groups so the entry point is consistent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../routing/app_router.dart';
import '../../auth/data/profile_repository.dart';
import 'user_avatar.dart';

class ProfileAvatarButton extends ConsumerWidget {
  const ProfileAvatarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).value;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: () => context.push(AppRoutes.profile),
        customBorder: const CircleBorder(),
        // Center, because AppBar.leading hands its child TIGHT 56px
        // constraints — a SizedBox cannot shrink out of those, so without this
        // the circle stretches into a toolbar-sized oval. Center takes the
        // tight box and places the real 32px avatar in the middle of it.
        child: Center(
          child: UserAvatar(
            profile: profile,
            radius: 16,
            // Solid rather than the usual tint: this one sits on the app
            // bar, where a translucent circle would read as a smudge.
            background: AppColors.primary,
            foreground: AppColors.onAccent,
          ),
        ),
      ),
    );
  }
}
