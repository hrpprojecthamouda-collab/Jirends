/// Group detail (Type 1, selection group). Manage the friends in this private
/// group: add from your friends, remove, rename, delete. Adding a member here
/// requires they're your friend (the group_members RLS enforces it).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/profile.dart';
import '../../friends/application/friend_list_controller.dart';
import '../application/group_list_controller.dart';
import 'group_dialogs.dart';
import 'member_picker.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final group = ref
        .watch(groupListProvider)
        .value
        ?.where((g) => g.id == groupId)
        .firstOrNull;
    final members = ref.watch(groupMembersProvider(groupId));

    ref.listen(groupActionsControllerProvider, (_, n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(group?.name ?? t.groupMembers),
        actions: [
          IconButton(
            tooltip: t.groupDelete,
            icon: const Icon(Icons.delete_outline, color: AppColors.coral),
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                message: t.groupDeleteConfirm(group?.name ?? ''),
                confirmLabel: t.groupDelete,
              );
              if (ok && context.mounted) {
                await ref
                    .read(groupActionsControllerProvider.notifier)
                    .delete(groupId);
                if (context.mounted) context.pop();
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addFriend(context, ref, members.value ?? const []),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(t.groupAddMember),
      ),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(messageForError(e))),
        data: (list) => list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(t.groupAddMember,
                      style: const TextStyle(color: AppColors.inkMuted)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  for (final p in list)
                    Card(
                      child: ListTile(
                        leading: _Avatar(p),
                        title: Text(p.handle ?? '…'),
                        trailing: IconButton(
                          icon: const Icon(Icons.person_remove_outlined,
                              color: AppColors.inkMuted),
                          onPressed: () => ref
                              .read(groupActionsControllerProvider.notifier)
                              .removeMember(groupId, p.id),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _addFriend(
      BuildContext context, WidgetRef ref, List<Profile> current) async {
    final t = AppLocalizations.of(context);
    final friends = ref.read(friendListProvider).value ?? const [];
    final currentIds = current.map((p) => p.id).toSet();
    final candidates =
        friends.where((f) => !currentIds.contains(f.id)).toList();

    final picked = await showMemberPicker(
      context,
      candidates: candidates,
      emptyMessage: t.groupNoFriendsToAdd,
    );
    if (picked != null) {
      await ref
          .read(groupActionsControllerProvider.notifier)
          .addMember(groupId, picked.id);
    }
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.profile);
  final Profile profile;
  @override
  Widget build(BuildContext context) {
    final initial = (profile.nickname ?? '?').characters.first.toUpperCase();
    return CircleAvatar(
      // ignore: deprecated_member_use
      backgroundColor: AppColors.blue.withOpacity(0.18),
      foregroundColor: AppColors.blue,
      child: Text(initial),
    );
  }
}
