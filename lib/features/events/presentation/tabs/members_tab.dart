/// Members tab — the member roster with role + RSVP. Your own row gets an RSVP
/// control. Organizers get a menu to add a friend or a group (the latter via
/// assign_group_to_event) and to remove members. RLS enforces all of this
/// regardless of what the UI shows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../groups/presentation/member_picker.dart';
import '../../application/event_detail_controller.dart';
import '../../data/event.dart';
import '../../data/event_detail_repository.dart';
import '../../data/event_member.dart';
import '../event_detail_screen.dart';
import '../../../profile/presentation/user_avatar.dart';
import '../../../groups/data/group_repository.dart';
import '../../../friends/data/friend_repository.dart';

class MembersTab extends ConsumerStatefulWidget {
  const MembersTab({super.key, required this.event});
  final Event event;

  @override
  ConsumerState<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<MembersTab> {
  /// Null = show everyone. Tapping the active chip clears it.
  RsvpStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
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
        final t = AppLocalizations.of(context);
        final isOrganizer = isCurrentUserOrganizer(members, myId);
        final organizerCount = members.where((m) => m.isOrganizer).length;

        // You first. Your row carries your own RSVP control, and hunting for
        // it at the bottom of a long roster is the one thing nobody should
        // have to do here. Everyone else keeps the server order.
        final ordered = [
          ...members.where((m) => m.userId == myId),
          ...members.where((m) => m.userId != myId),
        ];
        final shown = _filter == null
            ? ordered
            : [for (final m in ordered) if (m.rsvp == _filter) m];

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: isOrganizer
              ? _AddMenu(event: event, members: members)
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text(
                  t.membersCount(members.length),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.inkMuted,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              _RsvpFilters(
                members: members,
                selected: _filter,
                onChanged: (r) =>
                    setState(() => _filter = _filter == r ? null : r),
              ),
              const SizedBox(height: 6),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    t.membersNoneWithStatus,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                ),
              for (final m in shown)
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

/// In / Out / Maybe / AFK, each with its count. Tapping one narrows the roster
/// to that answer; tapping it again clears the filter. Replaces the old summary
/// card — the same numbers, but each one now does something.
///
/// AFK covers everyone who has not answered yet. It gets a chip like the rest:
/// on a big roster "who still owes me an answer" is the question an organizer
/// actually asks, and hunting an unfiltered list for absences is exactly what a
/// filter row should save you.
class _RsvpFilters extends StatelessWidget {
  const _RsvpFilters({
    required this.members,
    required this.selected,
    required this.onChanged,
  });
  final List<EventMember> members;
  final RsvpStatus? selected;
  final ValueChanged<RsvpStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    int countOf(RsvpStatus r) => members.where((m) => m.rsvp == r).length;

    // Wrap rather than Row so an oversized system font degrades to two rows
    // instead of overflowing.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final r in const [
          RsvpStatus.going,
          RsvpStatus.declined,
          RsvpStatus.maybe,
          RsvpStatus.pending,
        ])
          _RsvpChip(
            label: rsvpLabel(t, r),
            count: countOf(r),
            color: rsvpColor(r),
            selected: selected == r,
            onTap: () => onChanged(r),
          ),
      ],
    );
  }
}

/// One filter pill: a word and a count.
///
/// Hand-built rather than a ChoiceChip. A stock chip carries around 50px of
/// invisible chrome each — tap-target padding, label padding, theme padding —
/// and fitting on one row is the whole reason the words are short.
///
/// Measured from the shipped Baloo 2 binary, on a 360dp screen with 336dp of
/// usable width:
///
///   ChoiceChip  @16.1sp  In 76 + Out 87 + Maybe 107 + AFK 90 = 384dp  overflows
///   _RsvpChip   @13.8sp  In 45 + Out 54 + Maybe  71 + AFK 57 = 251dp  fits
///
/// The 85dp of slack is deliberate: it is what lets the row survive a user
/// with larger system text before Wrap has to break it.
///
/// Selection is carried by colour, and by Semantics.selected for anyone who
/// cannot see it.
class _RsvpChip extends StatelessWidget {
  const _RsvpChip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: .22) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : AppColors.outline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            '$label $count',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? color : AppColors.ink,
                ),
          ),
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
    // Boolean-only flag (see EventDetailRepository.fetchMemberConflicts) — no
    // event name/time ever reaches this widget, so it can't leak a hidden
    // event regardless of which one is conflicting.
    final conflicts = ref.watch(memberConflictsProvider(event.id)).value;
    final hasConflict = conflicts?[member.userId] ?? false;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: UserAvatar(profile: member.profile),
            title: Text(isMe ? '$handle (${t.youLabel})' : handle),
            subtitle: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(roleLabel,
                    style: TextStyle(color: AppColors.inkMuted)),
                if (hasConflict) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: t.memberConflictTooltip,
                    child: Icon(Icons.warning_amber_outlined,
                        size: 14, color: AppColors.coral),
                  ),
                ],
              ],
            ),
            trailing: canManage
                ? IconButton(
                    tooltip: isMe ? t.leaveEvent : t.removeMember,
                    icon: Icon(Icons.person_remove_outlined,
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

/// The wordless form of each answer: a tick, a question mark, a cross.
/// Paired with [rsvpColor] and always with [rsvpLabel] as tooltip/semantics,
/// so the meaning never rests on the glyph alone.
IconData rsvpIcon(RsvpStatus r) => switch (r) {
      RsvpStatus.going => Icons.check,
      RsvpStatus.maybe => Icons.question_mark,
      RsvpStatus.declined => Icons.close,
      RsvpStatus.pending => Icons.more_horiz,
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
    // Icons alone: a tick, a question mark and a cross say going / maybe / no
    // without a word, and three round buttons fit a row far better than three
    // labelled chips. The label survives as the tooltip AND the semantics
    // label, so a screen reader still announces each one by name.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in options)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: rsvpLabel(t, r),
              child: Semantics(
                label: rsvpLabel(t, r),
                selected: current == r,
                button: true,
                child: InkWell(
                  onTap: () => onChanged(r),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: current == r
                          ? rsvpColor(r).withValues(alpha: .18)
                          : Colors.transparent,
                      border: Border.all(
                        color: current == r ? rsvpColor(r) : AppColors.outline,
                        width: current == r ? 2 : 1,
                      ),
                    ),
                    child: Icon(
                      rsvpIcon(r),
                      size: 20,
                      color: current == r ? rsvpColor(r) : AppColors.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Organizer add menu: friend or group. A FAB that opens a bottom sheet
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
    }
  }

  Future<void> _addFriend(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final friends =
        await loadForPicker(
            context, ref.read(friendRepositoryProvider).fetchFriends());
    if (friends == null || !context.mounted) return;
    final memberIds = members.map((m) => m.userId).toSet();
    final candidates =
        friends.where((f) => !memberIds.contains(f.id)).toList();
    final picked = await showMemberPicker(context,
        candidates: candidates, emptyMessage: t.groupNoFriendsToAdd);
    if (picked != null) {
      await ref
          .read(memberActionsControllerProvider.notifier)
          .addMember(event.id, picked.id);
      if (!context.mounted) return;
      await _warnIfConflicted(context, ref, {picked.id: picked.handle ?? '…'});
    }
  }

  /// After an add succeeds, re-check the (just-invalidated) conflict flags and
  /// show a follow-up warning for anyone newly added who's double-booked.
  /// Boolean-only — names the PERSON (the organizer already knows who they
  /// just added) but never the other event.
  Future<void> _warnIfConflicted(
    BuildContext context,
    WidgetRef ref,
    Map<String, String> addedIdToHandle,
  ) async {
    if (addedIdToHandle.isEmpty) return;
    final t = AppLocalizations.of(context);
    final conflicts =
        await ref.read(eventDetailRepositoryProvider).fetchMemberConflicts(event.id);
    final conflictedNames = [
      for (final entry in addedIdToHandle.entries)
        if (conflicts[entry.key] == true) entry.value,
    ];
    if (conflictedNames.isEmpty || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.addedWithConflict(conflictedNames.join(', ')))),
    );
  }

  Future<void> _addGroup(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final groups =
        await loadForPicker(
            context, ref.read(groupRepositoryProvider).fetchGroups());
    if (groups == null || !context.mounted) return;
    final picked = await showGenericPicker(
      context,
      labels: {for (final g in groups) g.id: g.name},
      emptyMessage: t.noGroupsToAdd,
    );
    if (picked != null) {
      final beforeIds = members.map((m) => m.userId).toSet();
      final added = await ref
          .read(memberActionsControllerProvider.notifier)
          .addGroup(event.id, picked);
      if (added != null && context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(t.addedToEvent(added))));
        await _warnIfConflictedAmongNewMembers(context, ref, beforeIds);
      }
    }
  }


  /// A bulk group add doesn't return WHO was added, only a count — diff
  /// the member list before/after to find the new arrivals, then run the same
  /// boolean-only conflict check on each.
  Future<void> _warnIfConflictedAmongNewMembers(
    BuildContext context,
    WidgetRef ref,
    Set<String> beforeIds,
  ) async {
    final after =
        await ref.read(eventDetailRepositoryProvider).fetchMembers(event.id);
    final newMembers = after.where((m) => !beforeIds.contains(m.userId));
    final addedIdToHandle = {
      for (final m in newMembers) m.userId: m.profile.handle ?? '…',
    };
    if (!context.mounted) return;
    await _warnIfConflicted(context, ref, addedIdToHandle);
  }
}
