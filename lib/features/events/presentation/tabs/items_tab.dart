/// Items tab — assignable sub-tasks ("who brings dessert"). Any member can add,
/// tick, claim, or reassign; organizers/creators can delete. RLS enforces all of
/// it. Assignment uses the live member list as the candidate set.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/event_detail_controller.dart';
import '../../application/event_item_controller.dart';
import '../../data/event_item.dart';
import '../../data/event_member.dart';

class ItemsTab extends ConsumerStatefulWidget {
  const ItemsTab({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends ConsumerState<ItemsTab> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _input.text.trim();
    if (title.isEmpty) return;
    final ok = await ref
        .read(itemActionsControllerProvider.notifier)
        .add(widget.eventId, title);
    if (ok) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);
    final itemsAsync = ref.watch(eventItemsProvider(widget.eventId));
    final members = ref.watch(eventMembersProvider(widget.eventId)).value ?? const [];

    ref.listen(itemActionsControllerProvider, (_, n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    });

    return Column(
      children: [
        Expanded(
          child: itemsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(messageForError(e))),
            data: (items) => items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(t.itemsEmpty,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.inkMuted)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _ItemTile(
                      item: items[i],
                      myId: myId,
                      members: members,
                    ),
                  ),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(hintText: t.itemAddHint),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add),
                  tooltip: t.itemAdd,
                  onPressed: _add,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile(
      {required this.item, required this.myId, required this.members});
  final EventItem item;
  final String? myId;
  final List<EventMember> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final actions = ref.read(itemActionsControllerProvider.notifier);
    final assigneeHandle = item.assignee?.handle;

    return Card(
      child: ListTile(
        leading: Checkbox(
          value: item.isDone,
          activeColor: AppColors.teal,
          onChanged: (v) => actions.setDone(item.id, v ?? false),
        ),
        title: Text(
          item.title,
          style: item.isDone
              ? const TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: AppColors.inkMuted)
              : null,
        ),
        subtitle: Text(
          assigneeHandle == null
              ? t.itemUnassigned
              : (item.assignedTo == myId ? '${t.youLabel} · $assigneeHandle' : assigneeHandle),
          style: TextStyle(
              color: assigneeHandle == null ? AppColors.inkMuted : AppColors.blue),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.inkMuted),
          onSelected: (v) {
            switch (v) {
              case 'claim':
                actions.claim(item.id);
              case 'unassign':
                actions.assign(item.id, null);
              case 'delete':
                actions.delete(item.id);
              default:
                actions.assign(item.id, v); // v is a member userId
            }
          },
          itemBuilder: (context) => [
            if (item.assignedTo != myId)
              PopupMenuItem(value: 'claim', child: Text(t.itemClaim)),
            if (item.isAssigned)
              PopupMenuItem(value: 'unassign', child: Text(t.itemUnassign)),
            const PopupMenuDivider(),
            for (final m in members)
              if (m.userId != item.assignedTo)
                PopupMenuItem(
                  value: m.userId,
                  child: Text('${t.itemAssign}: ${m.profile.handle ?? '…'}'),
                ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: Text(t.itemDelete,
                  style: const TextStyle(color: AppColors.coral)),
            ),
          ],
        ),
      ),
    );
  }
}
