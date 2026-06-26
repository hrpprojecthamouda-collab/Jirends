/// Groups tab — two distinct concepts in one screen:
///   1. Selection groups (Type 1) — private to you; a shortcut to add several
///      friends to an event at once. Members never know they're in one.
///   2. Crews (Type 2) — shared, visible circles; every member sees the roster.
///
/// Both are dumb lists reading providers. Neither grants event visibility — that
/// stays with event_members (the cardinal rule); these only expand into members
/// at add-time, which happens on the event side.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/app_router.dart';
import '../../auth/application/auth_controller.dart';
import '../../notifications/presentation/widgets/notification_bell_button.dart';
import '../../profile/presentation/profile_avatar_button.dart';
import '../application/crew_list_controller.dart';
import '../application/group_list_controller.dart';
import 'group_dialogs.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final groups = ref.watch(groupListProvider);
    final crews = ref.watch(crewListProvider);

    // Surface action errors (create/delete/etc.) from either controller.
    ref.listen(groupActionsControllerProvider, (_, n) => _maybeError(context, n));
    ref.listen(crewActionsControllerProvider, (_, n) => _maybeError(context, n));

    return Scaffold(
      appBar: AppBar(
        leading: const ProfileAvatarButton(),
        title: Text(t.groupsTitle),
        actions: const [NotificationBellButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          // ── Selection groups (Type 1) ──────────────────────────────────
          _SectionHeader(
            title: t.groupsSelectionSection,
            hint: t.groupsSelectionHint,
            onAdd: () => showCreateNameDialog(
              context,
              title: t.groupCreate,
              label: t.groupName,
              onSubmit: (name) =>
                  ref.read(groupActionsControllerProvider.notifier).create(name),
            ),
          ),
          groups.when(
            loading: () => const _Loading(),
            error: (e, _) => _Error(messageForError(e)),
            data: (list) => list.isEmpty
                ? _EmptyLine(t.groupsSelectionEmpty)
                : Column(
                    children: [
                      for (final g in list)
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppColors.surfaceHi,
                              foregroundColor: AppColors.blue,
                              child: Icon(Icons.lock_outline),
                            ),
                            title: Text(g.name),
                            trailing: const Icon(Icons.chevron_right,
                                color: AppColors.inkMuted),
                            onTap: () =>
                                context.push(AppRoutes.groupDetail(g.id)),
                          ),
                        ),
                    ],
                  ),
          ),

          const SizedBox(height: 16),

          // ── Crews (Type 2) ─────────────────────────────────────────────
          _SectionHeader(
            title: t.crewsSection,
            hint: t.crewsHint,
            onAdd: () => showCreateNameDialog(
              context,
              title: t.crewCreate,
              label: t.crewName,
              onSubmit: (name) =>
                  ref.read(crewActionsControllerProvider.notifier).create(name),
            ),
          ),
          crews.when(
            loading: () => const _Loading(),
            error: (e, _) => _Error(messageForError(e)),
            data: (list) => list.isEmpty
                ? _EmptyLine(t.crewsEmpty)
                : Column(
                    children: [
                      for (final c in list)
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppColors.surfaceHi,
                              foregroundColor: AppColors.primary,
                              child: Icon(Icons.groups_2_outlined),
                            ),
                            title: Text(c.name),
                            trailing: const Icon(Icons.chevron_right,
                                color: AppColors.inkMuted),
                            onTap: () =>
                                context.push(AppRoutes.crewDetail(c.id)),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _maybeError(BuildContext context, AsyncValue<void> next) {
    if (next.hasError && !next.isLoading) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(messageForError(next.error!))));
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.title, required this.hint, required this.onAdd});
  final String title;
  final String hint;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton.filledTonal(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Text(hint,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.inkMuted)),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _Error extends StatelessWidget {
  const _Error(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message, style: const TextStyle(color: AppColors.coral)),
      );
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(message,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.inkMuted)),
      );
}
