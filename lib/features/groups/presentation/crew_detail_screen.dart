/// Crew detail (Type 2, shared & visible). Every member sees the roster. Only
/// the OWNER can add/remove members, rename, or delete — the UI hides those
/// affordances for non-owners (and RLS enforces it regardless). Members are
/// picked from your friends for convenience, though crews don't require
/// friendship.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/profile.dart';
import '../../friends/application/friend_list_controller.dart';
import '../application/crew_list_controller.dart';
import 'group_dialogs.dart';
import 'member_picker.dart';

class CrewDetailScreen extends ConsumerWidget {
  const CrewDetailScreen({super.key, required this.crewId});
  final String crewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final crew = ref
        .watch(crewListProvider)
        .value
        ?.where((c) => c.id == crewId)
        .firstOrNull;
    final members = ref.watch(crewMembersProvider(crewId));
    final myId = ref.watch(currentUserIdProvider);
    final isOwner = crew != null && crew.ownerId == myId;

    ref.listen(crewActionsControllerProvider, (_, n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(crew?.name ?? t.crewMembers),
        actions: [
          if (isOwner)
            IconButton(
              tooltip: t.crewDelete,
              icon: const Icon(Icons.delete_outline, color: AppColors.coral),
              onPressed: () async {
                final ok = await showConfirmDialog(
                  context,
                  message: t.crewDeleteConfirm(crew.name),
                  confirmLabel: t.crewDelete,
                );
                if (ok && context.mounted) {
                  await ref
                      .read(crewActionsControllerProvider.notifier)
                      .delete(crewId);
                  if (context.mounted) context.pop();
                }
              },
            ),
        ],
      ),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: () =>
                  _addMember(context, ref, members.value ?? const []),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(t.crewAddMember),
            )
          : null,
      body: Column(
        children: [
          // Ownership banner.
          Container(
            width: double.infinity,
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(isOwner ? Icons.shield_outlined : Icons.visibility_outlined,
                    size: 16, color: AppColors.inkMuted),
                const SizedBox(width: 8),
                Text(isOwner ? t.crewYouOwn : t.crewYouAreMember,
                    style: const TextStyle(color: AppColors.inkMuted)),
              ],
            ),
          ),
          Expanded(
            child: members.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(messageForError(e))),
              data: (list) => ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  for (final p in list)
                    Card(
                      child: ListTile(
                        leading: _Avatar(p),
                        title: Text(p.handle ?? '…'),
                        trailing: isOwner
                            ? IconButton(
                                icon: const Icon(Icons.person_remove_outlined,
                                    color: AppColors.inkMuted),
                                onPressed: () => ref
                                    .read(crewActionsControllerProvider.notifier)
                                    .removeMember(crewId, p.id),
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addMember(
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
          .read(crewActionsControllerProvider.notifier)
          .addMember(crewId, picked.id);
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
      backgroundColor: AppColors.violet.withOpacity(0.18),
      foregroundColor: AppColors.violet,
      child: Text(initial),
    );
  }
}
