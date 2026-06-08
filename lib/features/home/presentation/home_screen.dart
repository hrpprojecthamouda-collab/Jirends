/// Home — an activity feed of recent goings-on across the user's VISIBLE events
/// (comments, new items). Every entry is derived from a member-scoped row, so it
/// can never name or hint at an event the user can't see (cardinal rule, safe by
/// construction — see ActivityRepository). Tapping an entry opens its event.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/app_router.dart';
import '../../auth/application/auth_controller.dart';
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
    final (icon, color, title) = switch (item.kind) {
      ActivityKind.comment => (
          Icons.chat_bubble_outline,
          AppColors.blue,
          t.activityComment(item.actorHandle ?? t.activitySomeone, item.eventTitle),
        ),
      ActivityKind.item => (
          Icons.check_box_outlined,
          AppColors.teal,
          t.activityItem(item.eventTitle),
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
