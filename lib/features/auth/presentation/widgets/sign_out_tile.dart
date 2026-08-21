/// Signing out, as one row that behaves identically wherever it appears.
///
/// It sits in two places on purpose: on the Profile screen, because that is
/// where your identity is and where you look for it, and at the bottom of
/// Settings, where it has always been. Both use THIS widget rather than their
/// own copy — a sign-out that confirms in one place and not the other is worse
/// than either behaviour on its own.
///
/// Clearing cached data is deliberately not this widget's job: every per-user
/// provider (events, friends, crews, groups, notifications, the activity feed,
/// the profile) already watches currentSessionProvider, so they all re-subscribe
/// the moment the session drops. The router's redirect guard does the rest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/auth_controller.dart';

/// Ask before ending the session.
///
/// One mis-tap on a list row shouldn't sign you out and make you find your
/// password again — and unlike most destructive actions this one has no undo
/// short of signing back in.
Future<bool> confirmSignOut(BuildContext context) async {
  final t = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.signOutConfirmTitle),
      content: Text(t.signOutConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(t.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(t.settingsSignOut,
              style: TextStyle(color: AppColors.coral)),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class SignOutTile extends ConsumerStatefulWidget {
  const SignOutTile({super.key});

  @override
  ConsumerState<SignOutTile> createState() => _SignOutTileState();
}

class _SignOutTileState extends ConsumerState<SignOutTile> {
  /// Local, NOT `authControllerProvider.isLoading`. An AsyncNotifier sits in
  /// AsyncLoading until its build() future resolves, so reading the shared
  /// state rendered this row disabled and spinning before anyone had touched
  /// it. It should also only spin for its OWN sign-out, not because some other
  /// auth action happens to be in flight.
  bool _busy = false;

  Future<void> _signOut() async {
    if (!await confirmSignOut(context) || !mounted) return;

    setState(() => _busy = true);
    await ref.read(authControllerProvider.notifier).signOut();
    // On success the router has already redirected to /sign-in and this widget
    // is gone; there is nothing left to update.
    if (!mounted) return;
    setState(() => _busy = false);

    // A failed sign-out used to do nothing at all — the error landed on the
    // controller's state and no screen was listening, so the row just looked
    // broken.
    final error = ref.read(authControllerProvider).error;
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(messageForError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return ListTile(
      enabled: !_busy,
      leading: _busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.logout, color: AppColors.coral),
      title: Text(
        t.settingsSignOut,
        style: TextStyle(color: _busy ? AppColors.inkMuted : AppColors.coral),
      ),
      onTap: _busy ? null : _signOut,
    );
  }
}
