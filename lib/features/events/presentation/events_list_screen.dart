/// Events — the Events branch of the app shell. Hosts a List / Agenda toggle.
/// Renders whatever [eventListProvider] returns; it does NOT decide what is
/// visible (that is the database's job). Loading and error states are handled
/// here, never swallowed.
///
/// Both views read the same RLS-scoped event list. The Agenda must never become
/// a free/busy overlay that leaks a hidden event's time — it only ever shows
/// the user's own visible events on their days.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/app_router.dart';
import '../../auth/application/auth_controller.dart';
import '../../notifications/presentation/widgets/notification_bell_button.dart';
import '../../profile/presentation/profile_avatar_button.dart';
import '../application/event_grouping.dart';
import '../application/event_list_controller.dart';
import '../data/event.dart';
import 'widgets/agenda_view.dart';
import 'widgets/event_card.dart';

enum _EventsView { list, agenda }

/// The chips across the top of the list, in display order — [byMe] leads.
///
/// All but [byMe] are the buckets from [EventBucket], a true partition. [byMe]
/// is different in kind: it cuts across all four, so an event appears both
/// there and in its bucket. Kept as a separate enum so that distinction is
/// visible rather than buried.
enum _Shelf { byMe, confirmed, planning, past, cancelled }

/// Which shelf to open on before the user picks one — deliberately NOT the
/// display order. "By me" sits leftmost because it's the one you reach for,
/// but landing there by default would bury everyone else's events behind a
/// tap. So the app still opens on Confirmed, falling through to whatever has
/// content.
const _fallbackOrder = <_Shelf>[
  _Shelf.confirmed,
  _Shelf.planning,
  _Shelf.past,
  _Shelf.cancelled,
  _Shelf.byMe,
];

EventBucket? _bucketFor(_Shelf shelf) => switch (shelf) {
      _Shelf.confirmed => EventBucket.confirmed,
      _Shelf.planning => EventBucket.planning,
      _Shelf.past => EventBucket.past,
      _Shelf.cancelled => EventBucket.cancelled,
      _Shelf.byMe => null,
    };

class EventsListScreen extends ConsumerStatefulWidget {
  const EventsListScreen({super.key});

  @override
  ConsumerState<EventsListScreen> createState() => _EventsListScreenState();
}

class _EventsListScreenState extends ConsumerState<EventsListScreen> {
  _EventsView _view = _EventsView.list;

  /// Null until the user picks one, so the first render can land on a shelf
  /// that actually has something in it (see [_GroupedList]). Landing on an
  /// empty "Confirmed" would make the app look broken for anyone who hasn't
  /// confirmed anything yet.
  _Shelf? _shelf;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final eventsAsync = ref.watch(eventListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const ProfileAvatarButton(),
        title: Text(t.eventsTitle),
        // List / Agenda used to be a labelled SegmentedButton on its own row
        // under the title, which cost ~56px of height on every scroll of the
        // screen for a control that is touched once in a while. Up here as two
        // icons it costs nothing, and the labels survive as tooltips and
        // semantics labels.
        actions: [
          _ViewToggle(
            view: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          const NotificationBellButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.createEvent),
        icon: const Icon(Icons.add),
        label: Text(t.eventsNew),
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: messageForError(err),
          retryLabel: t.commonRetry,
          onRetry: () => ref.invalidate(eventListProvider),
        ),
        data: (events) => switch (_view) {
          _EventsView.agenda => AgendaView(
              events: events,
              onOpenEvent: (e) => context.push(AppRoutes.eventDetail(e.id)),
            ),
          _EventsView.list => events.isEmpty
              ? _EmptyView(message: t.eventsEmpty)
              : _GroupedList(
                  events: events,
                  shelf: _shelf,
                  myUserId: ref.watch(currentUserIdProvider),
                  // Empty while loading: cards omit the count rather than
                  // flashing a wrong one.
                  memberCounts:
                      ref.watch(eventMemberCountsProvider).value ?? const {},
                  onShelfChanged: (s) => setState(() => _shelf = s),
                  onRefresh: () async {
                    ref.invalidate(eventListProvider);
                    ref.invalidate(eventMemberCountsProvider);
                  },
                ),
        },
      ),
    );
  }
}

/// The list view: a row of shelf chips (with counts) over a date-grouped list.
///
/// Switching chips changes which shelf you're looking at; it never hides
/// anything the database returned. That distinction matters — this is
/// presentation, not the visibility model.
/// List / Agenda, as two icons in the app bar.
///
/// Icon-only on purpose: the two views are visually unmistakable once you have
/// seen them once, and the labelled version was eating a whole row. Tooltip and
/// Semantics keep the names for anyone who needs them.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final _EventsView view;
  final ValueChanged<_EventsView> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ViewIcon(
          icon: Icons.view_list_outlined,
          label: t.eventsViewList,
          selected: view == _EventsView.list,
          onTap: () => onChanged(_EventsView.list),
        ),
        _ViewIcon(
          icon: Icons.calendar_month_outlined,
          label: t.eventsViewAgenda,
          selected: view == _EventsView.agenda,
          onTap: () => onChanged(_EventsView.agenda),
        ),
      ],
    );
  }
}

class _ViewIcon extends StatelessWidget {
  const _ViewIcon({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // A tint rather than an outline: in an app bar an outlined
              // circle reads as a button you have not pressed yet.
              color: selected
                  ? AppColors.primary.withValues(alpha: .16)
                  : Colors.transparent,
            ),
            child: Icon(
              icon,
              size: 22,
              color: selected ? AppColors.primary : AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.events,
    required this.shelf,
    required this.myUserId,
    required this.memberCounts,
    required this.onShelfChanged,
    required this.onRefresh,
  });

  final List<Event> events;

  /// Null means "nothing chosen yet" — fall back to the first shelf that has
  /// events, so the list never opens on an empty one.
  final _Shelf? shelf;
  final String? myUserId;

  /// Attendee count per event id; missing while the stream is still loading.
  final Map<String, int> memberCounts;
  final ValueChanged<_Shelf> onShelfChanged;
  final Future<void> Function() onRefresh;

  String _shelfLabel(AppLocalizations t, _Shelf s) => switch (s) {
        _Shelf.confirmed => t.eventsViewConfirmed,
        _Shelf.planning => t.eventsViewPlanning,
        _Shelf.past => t.eventsViewPast,
        _Shelf.cancelled => t.eventsViewCancelled,
        _Shelf.byMe => t.eventsViewByMe,
      };

  String _emptyMessage(AppLocalizations t, _Shelf s) => switch (s) {
        _Shelf.confirmed => t.eventsNoneConfirmed,
        _Shelf.planning => t.eventsNonePlanning,
        _Shelf.past => t.eventsNonePast,
        _Shelf.cancelled => t.eventsNoneCancelled,
        _Shelf.byMe => t.eventsNoneByMe,
      };

  String _bandLabel(AppLocalizations t, DateBand band) => switch (band) {
        DateBand.undated => t.eventsGroupUndated,
        DateBand.thisWeek => t.eventsGroupThisWeek,
        DateBand.nextWeek => t.eventsGroupNextWeek,
        DateBand.laterThisMonth => t.eventsGroupLaterThisMonth,
        DateBand.laterThisYear => t.eventsGroupLaterThisYear,
        DateBand.beyond => t.eventsGroupBeyond,
        DateBand.past => t.eventsViewPast,
      };

  /// The events behind each chip. The four buckets partition the list; "By me"
  /// is drawn from the whole list and therefore overlaps them.
  List<Event> _eventsFor(
    _Shelf s,
    Map<EventBucket, List<Event>> split,
  ) {
    final bucket = _bucketFor(s);
    return bucket == null ? createdBy(events, myUserId) : split[bucket]!;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final now = DateTime.now();
    final split = splitIntoBuckets(events, now);
    final counts = {
      for (final s in _Shelf.values) s: _eventsFor(s, split).length,
    };

    final active = shelf ??
        _fallbackOrder.firstWhere(
          (s) => counts[s]! > 0,
          orElse: () => _Shelf.confirmed,
        );
    final shown = _eventsFor(active, split);

    // Past and cancelled read as pure history: newest first, no date bands,
    // since "upcoming this week" is meaningless once it's behind you. "By me"
    // spans both, so it keeps the bands (with a Past band at the end).
    final isHistory = active == _Shelf.past || active == _Shelf.cancelled;

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final s in _Shelf.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: s == active,
                    onSelected: (_) => onShelfChanged(s),
                    label: Text('${_shelfLabel(t, s)}  ${counts[s]}'),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: shown.isEmpty
                ? _ScrollableMessage(message: _emptyMessage(t, active))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    children: isHistory
                        ? [
                            for (final e in sortedNewestFirst(shown))
                              _card(context, e),
                          ]
                        : [
                            for (final section in dateSections(shown, now)) ...[
                              _SectionHeader(_bandLabel(t, section.band)),
                              for (final e in section.events) _card(context, e),
                            ],
                          ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, Event e) => EventCard(
        event: e,
        attendeeCount: memberCounts[e.id],
        onTap: () => context.push(AppRoutes.eventDetail(e.id)),
      );
}

/// A date-band caption between groups of cards.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.inkMuted,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

/// An empty-bucket message that still scrolls, so pull-to-refresh works when
/// the chosen bucket happens to be empty.
class _ScrollableMessage extends StatelessWidget {
  const _ScrollableMessage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted),
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration_outlined,
                size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(message,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
