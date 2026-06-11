/// Polls tab — the event's polls. Any member can create a poll (date/place
/// kinds organizer-only) and cast one vote; the poll's creator closes it. All
/// RLS-scoped; this just renders what the providers return.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/event_detail_controller.dart';
import '../../application/poll_controller.dart';
import '../event_detail_screen.dart';
import '../widgets/create_poll_sheet.dart';
import '../widgets/poll_card.dart';

class PollsTab extends ConsumerWidget {
  const PollsTab({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);
    final members = ref.watch(eventMembersProvider(eventId)).value ?? const [];
    final isOrganizer = isCurrentUserOrganizer(members, myId);
    final pollsAsync = ref.watch(eventPollsProvider(eventId));

    ref.listen(pollActionsControllerProvider, (_, n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            showCreatePollSheet(context, eventId: eventId, isOrganizer: isOrganizer),
        icon: const Icon(Icons.add),
        label: Text(t.pollNew),
      ),
      // Keep the last-loaded polls on screen while the provider re-fetches
      // (after a vote/close it invalidates, and we don't want the list to blank
      // to a spinner each time). Only show the spinner on the very first load.
      body: pollsAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(messageForError(e))),
        data: (polls) => polls.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(t.pollsEmpty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.inkMuted)),
                ),
              )
            // Pull-to-refresh: the poll list is a one-shot fetch invalidated by
            // the local user's own actions, so this is how you pick up OTHER
            // members' votes/closes without leaving the tab. (An earlier commit
            // removed this chasing a layout crash whose real cause turned out
            // to be the Material buttons in the poll card, since replaced.)
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(eventPollsProvider(eventId)),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  children: [
                    for (final v in polls)
                      PollCard(view: v, isEventOrganizer: isOrganizer),
                  ],
                ),
              ),
      ),
    );
  }
}
