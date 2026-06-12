/// Members tab — the member roster with role + RSVP. Your own row gets an RSVP
/// control. Organizers get a menu to add a friend / group / crew (via the
/// already-shipped assign_* RPCs) and to remove members. RLS enforces all of
/// this regardless of what the UI shows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../friends/application/friend_list_controller.dart';
import '../../../groups/application/crew_list_controller.dart';
import '../../../groups/application/group_list_controller.dart';
import '../../../groups/presentation/member_picker.dart';
import '../../application/event_detail_controller.dart';
import '../../data/event.dart';
import '../../data/event_member.dart';
import '../event_detail_screen.dart';

class MembersTab extends ConsumerWidget {
  const MembersTab({super.key, required this.event});
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserIdProvider);
    final membersAsync = ref.watch(eventMembersProvider(event.id));

    ref.listen(memberActionsControllerProvider, (_, n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    });

    return membersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(messageForError(e))),
      data: (members) {
        final isOrganizer = isCurrentUserOrganizer(members, myId);
        final organizerCount = members.where((m) => m.isOrganizer).length;
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: isOrganizer
              ? _AddMenu(event: event, members: members)
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              _RsvpSummaryCard(members: members),
              for (final m in members)
                _MemberTile(
                  event: event,
                  member: m,
                  isMe: m.userId == myId,
                  // You can manage (remove/leave) if you're an organizer or it's
                  // your own row — EXCEPT the last organizer can't be removed or
                  // leave, since that would orphan the event. (DB enforces too.)
                  canManage: (isOrganizer || m.userId == myId) &&
                      !(m.isOrganizer && organizerCount <= 1),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Counts + a stacked proportion bar for the event's RSVPs: going / maybe /
/// declined / no reply (pending). Pure presentation over the already-loaded
/// member list — no extra fetch, no visibility logic.
class _RsvpSummaryCard extends StatelessWidget {
  const _RsvpSummaryCard({required this.members});
  final List<EventMember> members;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final going = members.where((m) => m.rsvp == RsvpStatus.going).length;
    final maybe = members.where((m) => m.rsvp == RsvpStatus.maybe).length;
    final declined = members.where((m) => m.rsvp == RsvpStatus.declined).length;
    final noReply = members.length - going - maybe - declined;

    // (status, count, color) in display order.
    final entries = <(String, int, Color)>[
      (t.rsvpGoing, going, AppColors.teal),
      (t.rsvpMaybe, maybe, AppColors.yellow),
      (t.rsvpDeclined, declined, AppColors.coral),
      (t.membersNoReply, noReply, AppColors.inkMuted),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.membersCount(members.length),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            // Stacked proportion bar: flex-only segments in a bounded Row —
            // the same safe idiom as the poll tally bars.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    for (final (_, count, color) in entries)
                      if (count > 0)
                        Expanded(
                          flex: count,
                          child: Container(
                            // ignore: deprecated_member_use
                            color: color.withOpacity(
                                color == AppColors.inkMuted ? 0.35 : 0.85),
                          ),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final (label, count, color) in entries)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text('$count $label',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: AppColors.inkMuted)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.event,
    required this.member,
    required this.isMe,
    required this.canManage,
  });
  final Event event;
  final EventMember member;
  final bool isMe;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final handle = member.profile.handle ?? '…';
    final roleLabel =
        member.isOrganizer ? t.memberRoleOrganizer : t.memberRoleMember;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              // ignore: deprecated_member_use
              backgroundColor: AppColors.primary.withOpacity(0.18),
              foregroundColor: AppColors.primary,
              child: Text(
                  (member.profile.nickname ?? '?').characters.first.toUpperCase()),
            ),
            title: Text(isMe ? '$handle (${t.youLabel})' : handle),
            subtitle: Text(roleLabel,
                style: const TextStyle(color: AppColors.inkMuted)),
            trailing: canManage
                ? IconButton(
                    tooltip: isMe ? t.leaveEvent : t.removeMember,
                    icon: const Icon(Icons.person_remove_outlined,
                        color: AppColors.inkMuted),
                    onPressed: () => ref
                        .read(memberActionsControllerProvider.notifier)
                        .removeMember(event.id, member.userId),
                  )
                : _RsvpBadge(member.rsvp),
          ),
          // Your own RSVP control.
          if (isMe)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _RsvpPicker(
                  current: member.rsvp,
                  onChanged: (r) => ref
                      .read(memberActionsControllerProvider.notifier)
                      .setMyRsvp(event.id, r),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String rsvpLabel(AppLocalizations t, RsvpStatus r) => switch (r) {
      RsvpStatus.pending => t.rsvpPending,
      RsvpStatus.going => t.rsvpGoing,
      RsvpStatus.maybe => t.rsvpMaybe,
      RsvpStatus.declined => t.rsvpDeclined,
    };

Color rsvpColor(RsvpStatus r) => switch (r) {
      RsvpStatus.going => AppColors.teal,
      RsvpStatus.maybe => AppColors.yellow,
      RsvpStatus.declined => AppColors.coral,
      RsvpStatus.pending => AppColors.inkMuted,
    };

class _RsvpBadge extends StatelessWidget {
  const _RsvpBadge(this.rsvp);
  final RsvpStatus rsvp;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = rsvpColor(rsvp);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: c.withOpacity(0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(rsvpLabel(t, rsvp),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: c, fontWeight: FontWeight.w600)),
    );
  }
}

class _RsvpPicker extends StatelessWidget {
  const _RsvpPicker({required this.current, required this.onChanged});
  final RsvpStatus current;
  final ValueChanged<RsvpStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    const options = [RsvpStatus.going, RsvpStatus.maybe, RsvpStatus.declined];
    return Wrap(
      spacing: 8,
      children: [
        for (final r in options)
          ChoiceChip(
            label: Text(rsvpLabel(t, r)),
            selected: current == r,
            selectedColor: rsvpColor(r),
            onSelected: (_) => onChanged(r),
          ),
      ],
    );
  }
}

/// Organizer add menu: friend / group / crew. A FAB that opens a bottom sheet
/// with the three add options.
class _AddMenu extends ConsumerWidget {
  const _AddMenu({required this.event, required this.members});
  final Event event;
  final List<EventMember> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return FloatingActionButton.extended(
      onPressed: () => _openMenu(context, ref),
      icon: const Icon(Icons.person_add_alt_1),
      label: Text(t.addFriend),
    );
  }

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(t.addFriend),
              onTap: () => Navigator.of(context).pop('friend'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(t.addGroup),
              onTap: () => Navigator.of(context).pop('group'),
            ),
            ListTile(
              leading: const Icon(Icons.groups_2_outlined),
              title: Text(t.addCrew),
              onTap: () => Navigator.of(context).pop('crew'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case 'friend':
        await _addFriend(context, ref);
      case 'group':
        await _addGroup(context, ref);
      case 'crew':
        await _addCrew(context, ref);
    }
  }

  Future<void> _addFriend(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final friends = ref.read(friendListProvider).value ?? const [];
    final memberIds = members.map((m) => m.userId).toSet();
    final candidates =
        friends.where((f) => !memberIds.contains(f.id)).toList();
    final picked = await showMemberPicker(context,
        candidates: candidates, emptyMessage: t.groupNoFriendsToAdd);
    if (picked != null) {
      await ref
          .read(memberActionsControllerProvider.notifier)
          .addMember(event.id, picked.id);
    }
  }

  Future<void> _addGroup(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final groups = ref.read(groupListProvider).value ?? const [];
    final picked = await showGenericPicker(
      context,
      labels: {for (final g in groups) g.id: g.name},
      emptyMessage: t.noGroupsToAdd,
    );
    if (picked != null) {
      final added = await ref
          .read(memberActionsControllerProvider.notifier)
          .addGroup(event.id, picked);
      if (added != null && context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(t.addedToEvent(added))));
      }
    }
  }

  Future<void> _addCrew(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final crews = ref.read(crewListProvider).value ?? const [];
    final picked = await showGenericPicker(
      context,
      labels: {for (final c in crews) c.id: c.name},
      emptyMessage: t.noCrewsToAdd,
    );
    if (picked != null) {
      final added = await ref
          .read(memberActionsControllerProvider.notifier)
          .addCrew(event.id, picked);
      if (added != null && context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(t.addedToEvent(added))));
      }
    }
  }
}
