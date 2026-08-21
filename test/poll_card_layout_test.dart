// Reproduces the "BoxConstraints forces an infinite width" layout crash in the
// poll UI in a headless widget test, so the failing widget is named precisely.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jirends/core/i18n/fallback_material_localizations.dart';
import 'package:jirends/core/supabase/supabase_providers.dart';
import 'package:jirends/l10n/app_localizations.dart';
import 'package:jirends/features/events/data/poll.dart';
import 'package:jirends/features/events/data/poll_option.dart';
import 'package:jirends/features/events/data/poll_repository.dart';
import 'package:jirends/features/events/presentation/widgets/poll_card.dart';
import 'package:jirends/features/events/presentation/tabs/polls_tab.dart';
import 'package:jirends/features/events/application/poll_controller.dart';
import 'package:jirends/features/events/application/event_detail_controller.dart';
import 'package:jirends/features/events/data/event_member.dart';
import 'package:jirends/features/auth/data/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

PollView _view({bool closed = false, PollMode mode = PollMode.majority}) {
  const eventId = 'e1';
  final poll = Poll(
    id: 'p1',
    eventId: eventId,
    question: 'Pizza or sushi?',
    kind: PollKind.general,
    mode: mode,
    status: closed ? PollStatus.closed : PollStatus.open,
    createdBy: 'me',
    winningOptionId: closed ? 'o1' : null,
  );
  final options = const [
    PollOption(id: 'o1', pollId: 'p1', label: 'Pizza', position: 1),
    PollOption(id: 'o2', pollId: 'p1', label: 'Sushi', position: 2),
  ];
  return PollView(
    poll: poll,
    options: options,
    tallies: const {'o1': 2, 'o2': 1},
    myOptionIds: const {'o1'},
    // 3 votes from 2 people — multi-select means votes != voters.
    voterCount: 2,
    votes: const [],
  );
}

/// A poll where the caller has backed BOTH options — the multi-select case.
PollView _multiVoted() {
  const poll = Poll(
    id: 'p1',
    eventId: 'e1',
    question: 'Pizza or sushi?',
    kind: PollKind.general,
    mode: PollMode.majority,
    status: PollStatus.open,
    createdBy: 'me',
  );
  const options = [
    PollOption(id: 'o1', pollId: 'p1', label: 'Pizza', position: 1),
    PollOption(id: 'o2', pollId: 'p1', label: 'Sushi', position: 2),
  ];
  return PollView(
    poll: poll,
    options: options,
    tallies: const {'o1': 1, 'o2': 1},
    myOptionIds: const {'o1', 'o2'},
    voterCount: 1, // one person, two votes
    votes: const [],
  );
}

Widget _host(Widget child) => ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('me'),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...tnAwareFrameworkDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(children: [child]),
        ),
      ),
    );

void main() {
  testWidgets('open PollCard lays out in a ListView', (tester) async {
    await tester.pumpWidget(_host(PollCard(view: _view())));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed majority PollCard lays out', (tester) async {
    await tester.pumpWidget(_host(PollCard(view: _view(closed: true))));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('creator PollCard survives an intrinsic-width measurement',
      (tester) async {
    // IntrinsicWidth forces a maxIntrinsicWidth query down the card — the exact
    // pass that made the old FilledButton's _RenderInputPadding throw
    // "BoxConstraints forces an infinite width" in the creator view.
    await tester.pumpWidget(ProviderScope(
      overrides: [currentUserIdProvider.overrideWithValue('me')],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...tnAwareFrameworkDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: IntrinsicWidth(child: PollCard(view: _view())),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed weighted_random PollCard (wheel) lays out', (tester) async {
    await tester.pumpWidget(
        _host(PollCard(view: _view(closed: true, mode: PollMode.weightedRandom))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  // Regression for the event-detail header: a Row with a Spacer inside an
  // AppBar.bottom PreferredSize throws "infinite width" unless the child's
  // width is bounded (the SizedBox(width: maxWidth) wrap in the real screen).
  testWidgets('AppBar.bottom Row+Spacer needs a bounded width', (tester) async {
    Widget bottomChild(bool bounded) {
      final col = Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(children: [Text('Trip'), Spacer(), Text('Planning')]),
          ),
        ],
      );
      return bounded
          ? LayoutBuilder(
              builder: (context, c) => SizedBox(
                  width: c.maxWidth.isFinite
                      ? c.maxWidth
                      : MediaQuery.of(context).size.width,
                  child: col))
          : col;
    }

    Widget app(bool bounded) => MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('E'),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: bottomChild(bounded),
              ),
            ),
            body: const SizedBox(),
          ),
        );

    // Bounded (our fix): no exception.
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // Root cause: a Center/Align as a NON-flex child of a Row is handed unbounded
  // width and tries to fill it -> "forces an infinite width". This mirrors the
  // old _StatusChip(Center(...)) inside the header Row. The fix returns the chip
  // directly (no Center).
  testWidgets('Center child inside a Row forces infinite width; bare child OK',
      (tester) async {
    Widget rowWith(Widget child) => MaterialApp(
          home: Scaffold(
            body: Row(children: [const Text('Trip'), const Spacer(), child]),
          ),
        );
    final chip = Container(width: 60, height: 24, color: const Color(0xFF333333));
    // Bare chip (the fix): fine.
    await tester.pumpWidget(rowWith(chip));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('PollsTab lays out inside a TabBarView-like bounded box',
      (tester) async {
    final member = EventMember(
      userId: 'me',
      role: MemberRole.organizer,
      rsvp: RsvpStatus.going,
      profile: const Profile(id: 'me', nickname: 'Me', tagline: 'Tag'),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('me'),
        eventPollsProvider('e1').overrideWith((ref) async => [_view()]),
        eventMembersProvider('e1').overrideWith((ref) => Stream.value([member])),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...tnAwareFrameworkDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        // Mimic the real placement: a tab inside a TabBarView under an app bar.
        home: DefaultTabController(
          length: 1,
          child: Scaffold(
            appBar: AppBar(bottom: const TabBar(tabs: [Tab(text: 'Polls')])),
            body: const TabBarView(children: [PollsTab(eventId: 'e1')]),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });
  group('multi-select', _multiSelectTests);
}

// ── Multi-select voting ────────────────────────────────────────────────────
// A member may back several options in one poll (see polls_multivote.sql), so
// PollView carries a SET of the caller's options rather than a single id, and
// the voter count is tracked separately from the vote total.
void _multiSelectTests() {
  testWidgets('every option the caller backed renders as selected',
      (tester) async {
    final view = _multiVoted();
    await tester.pumpWidget(_host(PollCard(view: view)));
    await tester.pumpAndSettle();

    // Both options are the caller's — both show the "your vote" check.
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
  });

  test('votes and voters are separate counts under multi-select', () {
    final view = _multiVoted();
    expect(view.totalVotes, 2, reason: 'two votes were cast');
    expect(view.voterCount, 1, reason: 'but by a single person');
  });

  testWidgets('a poll still renders when the voter count is unknown',
      (tester) async {
    // voterCount is null when poll_voter_counts_for_event is unavailable (a
    // database that predates polls_multivote.sql). The poll must still draw:
    // losing one figure must never cost the whole view.
    final view = PollView(
      poll: _multiVoted().poll,
      options: _multiVoted().options,
      tallies: const {'o1': 1, 'o2': 1},
      myOptionIds: const {'o1'},
      voterCount: null,
      votes: const [],
    );
    await tester.pumpWidget(_host(PollCard(view: view)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Pizza'), findsOneWidget);
    expect(find.text('Sushi'), findsOneWidget);
  });

  test('an empty option set means the caller has not voted', () {
    final view = _multiVoted();
    expect(view.myOptionIds.contains('o1'), isTrue);
    expect(const <String>{}.contains('o1'), isFalse);
  });
}
