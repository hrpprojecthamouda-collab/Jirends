/// HostAttendeesRow — the Meetup-style "who's involved" strip shown in the
/// Overview page under the description: the host on the left, the attendees'
/// avatars on the right. Tapping either side opens the full roster + RSVP
/// controls in an overlay panel.
///
/// Presentation only: it reads the same `eventMembersProvider` the roster
/// itself uses and derives everything from that already-visible list. No new
/// query, no visibility logic (visibility is the database's job — a
/// non-member never reaches this screen at all).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/event_detail_controller.dart';
import '../../data/event.dart';
import '../../data/event_member.dart';
import '../tabs/members_tab.dart';
import 'event_overlay_sheet.dart';
import '../../../profile/presentation/user_avatar.dart';

/// How many attendee avatars to show before collapsing into a "+N" bubble.
const _kMaxAvatars = 4;

class HostAttendeesRow extends ConsumerWidget {
  const HostAttendeesRow({super.key, required this.event});
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final members = ref.watch(eventMembersProvider(event.id)).value ?? const [];
    if (members.isEmpty) return const SizedBox.shrink();

    final host = members.where((m) => m.isOrganizer).firstOrNull;
    // Everyone who isn't the host we're already showing on the left.
    final attendees =
        members.where((m) => m.userId != host?.userId).toList(growable: false);

    void openRoster() => showEventOverlaySheet(
          context,
          title: t.detailTabMembers,
          child: MembersTab(event: event),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (host != null)
          Expanded(
            flex: 4,
            child: _Labelled(
              label: t.membersHost,
              child: InkWell(
                onTap: openRoster,
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    _Avatar(member: host, radius: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        host.profile.handle ?? '…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: _Labelled(
            label: t.membersAttendees(attendees.length),
            child: InkWell(
              onTap: openRoster,
              borderRadius: BorderRadius.circular(12),
              child: attendees.isEmpty
                  ? Text(t.membersNoneYet,
                      style: TextStyle(color: AppColors.inkMuted))
                  : _AvatarStack(attendees: attendees),
            ),
          ),
        ),
      ],
    );
  }
}

/// A small muted caption above its content, matching the Overview blocks.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          // Same weight AND colour as the section labels in overview_tab's
          // _Block — HOST and N ATTENDEES are card labels too and must not
          // read lighter than the ones directly above and below them.
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.ink,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// Overlapping avatars, capped at [_kMaxAvatars] with a "+N" bubble for the
/// rest.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.attendees});
  final List<EventMember> attendees;

  @override
  Widget build(BuildContext context) {
    final shown = attendees.take(_kMaxAvatars).toList();
    final overflow = attendees.length - shown.length;
    const radius = 18.0;
    const overlap = 12.0;

    return SizedBox(
      height: radius * 2,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (radius * 2 - overlap),
              child: _Avatar(member: shown[i], radius: radius, ringed: true),
            ),
          if (overflow > 0)
            Positioned(
              left: shown.length * (radius * 2 - overlap),
              child: Container(
                width: radius * 2,
                height: radius * 2,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHi,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflow',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.ink),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.member,
    required this.radius,
    this.ringed = false,
  });
  final EventMember member;
  final double radius;

  /// Draw a surface-coloured ring so overlapping avatars stay separable.
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    final avatar = UserAvatar(
      profile: member.profile,
      radius: radius,
    );
    if (!ringed) return avatar;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 2),
      ),
      child: avatar,
    );
  }
}
