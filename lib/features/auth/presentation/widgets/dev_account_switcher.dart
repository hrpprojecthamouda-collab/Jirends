/// DevAccountSwitcher — debug-only one-tap account switching for manual
/// testing (the surprise/visibility model needs constant switching between
/// accounts). Renders nothing if [kDevAccounts] is empty, which it always is
/// outside debug builds — this widget has zero footprint in release.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/dev_accounts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../application/auth_controller.dart';

class DevAccountSwitcher extends ConsumerWidget {
  const DevAccountSwitcher({super.key});

  Future<void> _switchTo(WidgetRef ref, DevAccount account) async {
    final notifier = ref.read(authControllerProvider.notifier);
    // Sign out first if there's a current session, then sign in as the
    // tapped account. The router redirects automatically on session change.
    await notifier.signOut();
    await notifier.signIn(email: account.email, password: account.password);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kDevAccounts.isEmpty) return const SizedBox.shrink();

    final loading = ref.watch(authControllerProvider).isLoading;

    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(next.error!))));
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'QUICK SWITCH (DEBUG)',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.inkMuted,
                  letterSpacing: 1.2,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final account in kDevAccounts)
              ActionChip(
                label: Text(account.label),
                onPressed: loading ? null : () => _switchTo(ref, account),
              ),
          ],
        ),
      ],
    );
  }
}
