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

class ProfileAvatarButton extends ConsumerWidget {
  const ProfileAvatarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initials = ref.watch(myProfileProvider).value?.initials ?? '?';
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: () => context.push(AppRoutes.profile),
        customBorder: const CircleBorder(),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.violet,
          foregroundColor: AppColors.onAccent,
          child: Text(
            initials,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
