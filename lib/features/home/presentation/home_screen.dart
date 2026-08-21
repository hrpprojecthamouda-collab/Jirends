/// Home — an activity feed of recent goings-on across the user's VISIBLE events
/// (comments). Every entry is derived from a member-scoped row, so it can never
/// name or hint at an event the user can't see (cardinal rule, safe by
/// construction — see ActivityRepository). Tapping an entry opens its event.
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
import '../../shell/presentation/placeholder_body.dart';
import '../application/activity_controller.dart';
import '../data/activity_item.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final feed = ref.watch(activityFeedProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const ProfileAvatarButton(),
        title: Text(t.homeTitle),
        actions: const [NotificationBellButton()],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(activityFeedProvider),
        child: feed.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(messageForError(e), textAlign: TextAlign.center),
            ),
          ]),
          data: (items) => items.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 80),
                  PlaceholderBody(
                      icon: Icons.bolt_outlined,
                      message: t.homeActivityEmpty),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _ActivityTile(item: items[i]),
                ),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});
  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final who = item.actorHandle ?? t.activitySomeone;
    // Icon + tint per activity, so the feed is scannable by shape and colour
    // before you read a word of it.
    final (icon, color, title) = switch (item.kind) {
      ActivityKind.comment => (
          Icons.chat_bubble_outline,
          AppColors.blue,
          t.activityComment(who, item.eventTitle),
        ),
      ActivityKind.reply => (
          Icons.forum_outlined,
          AppColors.blue,
          t.activityReply(who, item.eventTitle),
        ),
      ActivityKind.pollClosed => (
          Icons.how_to_vote_outlined,
          AppColors.teal,
          t.activityPollClosed(who, item.eventTitle),
        ),
      ActivityKind.pollReopened => (
          Icons.how_to_vote_outlined,
          AppColors.violet,
          t.activityPollReopened(who, item.eventTitle),
        ),
      ActivityKind.attachment => (
          Icons.attach_file,
          AppColors.yellow,
          t.activityAttachment(who, item.eventTitle),
        ),
      ActivityKind.rsvpGoing => (
          Icons.event_available_outlined,
          AppColors.teal,
          t.activityRsvpGoing(who, item.eventTitle),
        ),
      ActivityKind.rsvpNotGoing => (
          Icons.event_busy_outlined,
          AppColors.coral,
          t.activityRsvpNotGoing(who, item.eventTitle),
        ),
      ActivityKind.memberAdded => (
          Icons.person_add_alt_1,
          AppColors.violet,
          t.activityMemberAdded(who, item.eventTitle),
        ),
      // One entry per poll: two names inline, a count beyond that.
      ActivityKind.pollVoted => (
          Icons.how_to_vote_outlined,
          AppColors.blue,
          _votedLine(t, item),
        ),
    };

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          // ignore: deprecated_member_use
          backgroundColor: color.withOpacity(0.18),
          foregroundColor: color,
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: item.text == null
            ? null
            : Text(item.text!,
                maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(_ago(item.createdAt.toLocal()),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.inkMuted)),
        onTap: item.eventId.isEmpty
            ? null
            : () => context.push(AppRoutes.eventDetail(item.eventId)),
      ),
    );
  }

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

/// "X and Y voted on the time poll in Z", switching on how many people voted.
///
/// A general poll has no distinguishing kind, and it cannot be written as an
/// empty {kind} placeholder: "voted on the {kind} poll" with kind = "" renders
/// as "voted on the  poll", double space and all, because the template owns the
/// spaces either side. Only a separate sentence can drop the word cleanly, so
/// the kindless case gets its own keys.
String _votedLine(AppLocalizations t, ActivityItem item) {
  final who =
      item.voterNames.isEmpty ? t.activitySomeone : item.voterNames.first;
  final kind = _pollKindLabel(t, item.pollKind);
  final event = item.eventTitle;

  if (kind == null) {
    return switch (item.voterCount) {
      0 || 1 => t.activityVotedOnePlain(who, event),
      2 => t.activityVotedTwoPlain(who, item.voterNames.last, event),
      _ => t.activityVotedManyPlain(item.voterCount, event),
    };
  }
  return switch (item.voterCount) {
    0 || 1 => t.activityVotedOne(who, kind, event),
    2 => t.activityVotedTwo(who, item.voterNames.last, kind, event),
    _ => t.activityVotedMany(item.voterCount, kind, event),
  };
}

/// The poll's kind as it reads in a sentence, or null for a general poll —
/// which has no kind to name at all. See [_votedLine].
String? _pollKindLabel(AppLocalizations t, String? kind) => switch (kind) {
      'date' => t.pollKindDate.toLowerCase(),
      'time' => t.pollKindTime.toLowerCase(),
      'place' => t.pollKindPlace.toLowerCase(),
      _ => null,
    };
