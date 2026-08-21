/// Profile — the user's identity (photo + handle) and the entry to Settings
/// (language, sign out), reached by tapping the avatar in any main app bar.
///
/// This is the only screen that can CHANGE the photo; every other avatar in the
/// app just renders whatever is on the profile.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/app_router.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/profile_repository.dart';
import '../application/avatar_controller.dart';
import '../../auth/presentation/widgets/sign_out_tile.dart';
import 'user_avatar.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final profile = ref.watch(myProfileProvider).value;
    final handle = profile?.handle ?? t.profileNoHandle;
    final busy = ref.watch(avatarControllerProvider).isLoading;

    // Upload failures surface here rather than inside the sheet, which has
    // usually closed by the time the server answers.
    ref.listen(avatarControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
              SnackBar(content: Text(messageForError(next.error!))));
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(t.profileTitle)),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: _AvatarPicker(
              busy: busy,
              hasPhoto: (profile?.avatarUrl ?? '').isNotEmpty,
              onPick: () =>
                  ref.read(avatarControllerProvider.notifier).pickAndUpload(),
              onRemove: () =>
                  ref.read(avatarControllerProvider.notifier).remove(),
              child: UserAvatar(
                profile: profile,
                radius: 44,
                background: AppColors.primary,
                foreground: AppColors.onAccent,
              ),
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
            trailing: Icon(Icons.chevron_right, color: AppColors.inkMuted),
            onTap: () => context.push(AppRoutes.settings),
          ),
          const Divider(),
          // Also in Settings, but this is where people look for it: one tap
          // from the avatar in any app bar, next to the identity it ends.
          const SignOutTile(),
        ],
      ),
    );
  }
}

/// The photo with a camera badge on it. Tapping anywhere on it offers "choose a
/// photo", plus "remove" once there is one to remove.
class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.busy,
    required this.hasPhoto,
    required this.onPick,
    required this.onRemove,
    required this.child,
  });

  final Widget child;
  final bool busy;
  final bool hasPhoto;
  final Future<bool> Function() onPick;
  final Future<bool> Function() onRemove;

  Future<void> _openMenu(BuildContext context) async {
    final t = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(hasPhoto ? t.avatarChange : t.avatarChoose),
              onTap: () {
                Navigator.of(sheet).pop();
                onPick();
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.coral),
                title: Text(t.avatarRemove,
                    style: TextStyle(color: AppColors.coral)),
                onTap: () {
                  Navigator.of(sheet).pop();
                  onRemove();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: hasPhoto ? t.avatarChange : t.avatarChoose,
      child: InkWell(
        onTap: busy ? null : () => _openMenu(context),
        customBorder: const CircleBorder(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            child,
            // The upload can take a moment on a slow connection; dimming the
            // photo under a spinner says "working" without moving the layout.
            if (busy)
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.ink.withValues(alpha: .45),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.outline),
                ),
                child: Icon(Icons.photo_camera_outlined,
                    size: 16, color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
