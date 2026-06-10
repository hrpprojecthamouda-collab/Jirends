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
    myOptionId: 'o1',
    closedVotes: const [],
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
}
