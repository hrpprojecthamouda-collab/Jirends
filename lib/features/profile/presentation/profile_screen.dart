/// Profile — the user's identity (avatar + handle) and the entry to Settings
/// (language, sign out), reached by tapping the avatar in any main app bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/app_router.dart';
import '../../auth/data/profile_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final profile = ref.watch(myProfileProvider).value;
    final initials = profile?.initials ?? '?';
    final handle = profile?.handle ?? t.profileNoHandle;

    return Scaffold(
      appBar: AppBar(title: Text(t.profileTitle)),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onAccent,
              child: Text(initials,
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(handle,
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 32),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(t.navSettings),
            trailing: const Icon(Icons.chevron_right, color: AppColors.inkMuted),
            onTap: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
    );
  }
}
