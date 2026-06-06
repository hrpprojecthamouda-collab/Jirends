/// Friends — the caller's directional address book. Add by handle, see your
/// friends, remove them. No visibility logic: the list is whatever the friends
/// RLS returns (always only your own rows).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/profile.dart';
import '../../shell/presentation/placeholder_body.dart';
import '../application/friend_list_controller.dart';

class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final friendsAsync = ref.watch(friendListProvider);

    // Surface add/remove errors as a snackbar.
    ref.listen(friendActionsControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(next.error!))));
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(t.friendsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(t.friendsAdd),
      ),
      body: friendsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(messageForError(err))),
        data: (friends) => friends.isEmpty
            ? PlaceholderBody(
                icon: Icons.people_outline, message: t.friendsEmpty)
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: friends.length,
                itemBuilder: (context, i) =>
                    _FriendTile(profile: friends[i]),
              ),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final controller = TextEditingController();
    final handle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.friendsAddByHandle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t.friendsHandleLabel,
            hintText: t.friendsHandleHint,
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(t.commonAdd),
          ),
        ],
      ),
    );
    controller.dispose();
    if (handle == null || handle.trim().isEmpty) return;

    final ok =
        await ref.read(friendActionsControllerProvider.notifier).addByHandle(handle);
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text(t.friendsAdded(handle.trim()))));
    }
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final handle = profile.handle ?? '…';
    final initial = (profile.nickname ?? '?').characters.first.toUpperCase();

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          // ignore: deprecated_member_use
          backgroundColor: AppColors.violet.withOpacity(0.18),
          foregroundColor: AppColors.violet,
          child: Text(initial),
        ),
        title: Text(handle),
        trailing: IconButton(
          tooltip: t.friendsRemove,
          icon: const Icon(Icons.person_remove_outlined,
              color: AppColors.inkMuted),
          onPressed: () => _confirmRemove(context, ref, handle),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, String handle) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.friendsRemoveConfirm(handle)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.friendsRemove),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(friendActionsControllerProvider.notifier).remove(profile.id);
    }
  }
}
