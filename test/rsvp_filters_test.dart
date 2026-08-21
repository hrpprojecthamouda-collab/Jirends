/// The RSVP filter chips in the attendees panel.
///
/// The vocabulary is In / Out / Maybe / AFK. AFK is the one that carries real
/// weight: it is the only way to see who still owes an answer, and "no reply"
/// is a state the roster stores rather than something anybody picks, so it is
/// easy to leave out by accident.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jirends/core/i18n/fallback_material_localizations.dart';
import 'package:jirends/core/supabase/supabase_providers.dart';
import 'package:jirends/core/theme/app_palette.dart';
import 'package:jirends/core/theme/app_theme.dart';
import 'package:jirends/features/auth/data/profile.dart';
import 'package:jirends/features/events/application/event_detail_controller.dart';
import 'package:jirends/features/events/data/event.dart';
import 'package:jirends/features/events/data/event_member.dart';
import 'package:jirends/features/events/presentation/tabs/members_tab.dart';
import 'package:jirends/l10n/app_localizations.dart';

final _now = DateTime(2026, 8, 20);

final _event = Event(
  id: 'e1',
  title: 'Apero',
  eventType: EventType.dinner,
  status: 'planning',
  createdBy: 'me',
  createdAt: _now,
  updatedAt: _now,
);

EventMember _member(String id, RsvpStatus rsvp, {bool organizer = false}) =>
    EventMember(
      userId: id,
      role: organizer ? MemberRole.organizer : MemberRole.member,
      rsvp: rsvp,
      profile: Profile(id: id, nickname: id, tagline: 'crew'),
    );

/// Two in, one out, one maybe, three with no reply.
final _roster = [
  _member('me', RsvpStatus.going, organizer: true),
  _member('ana', RsvpStatus.going),
  _member('bob', RsvpStatus.declined),
  _member('cyd', RsvpStatus.maybe),
  _member('dee', RsvpStatus.pending),
  _member('eli', RsvpStatus.pending),
  _member('fay', RsvpStatus.pending),
];

Future<void> _pump(WidgetTester tester) async {
  // A real phone width (360dp) but tall, so the lazy ListView builds every row
  // and a row count means what it says.
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      eventMembersProvider(_event.id).overrideWith((ref) => Stream.value(_roster)),
      memberConflictsProvider(_event.id)
          .overrideWith((ref) async => const <String, bool>{}),
    ],
    child: MaterialApp(
      theme: AppTheme.of(kDefaultPalette),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...tnAwareFrameworkDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MembersTab(event: _event),
    ),
  ));
  await tester.pumpAndSettle();
}

/// How many member rows the roster is currently showing.
int _rowCount(WidgetTester tester) =>
    tester.widgetList(find.byType(Card)).length;

void main() {
  testWidgets('four chips, in the agreed vocabulary, with their counts',
      (tester) async {
    await _pump(tester);

    expect(find.widgetWithText(InkWell, 'In 2'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Out 1'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Maybe 1'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'AFK 3'), findsOneWidget);
  });

  testWidgets('the old wording is gone', (tester) async {
    await _pump(tester);
    for (final old in ['Going', 'Declined', 'Pending']) {
      expect(find.textContaining(old), findsNothing, reason: old);
    }
  });

  testWidgets('AFK narrows the roster to people who have not answered',
      (tester) async {
    await _pump(tester);
    expect(_rowCount(tester), 7);

    await tester.tap(find.widgetWithText(InkWell, 'AFK 3'));
    await tester.pumpAndSettle();
    expect(_rowCount(tester), 3);
  });

  testWidgets('tapping the active chip clears the filter', (tester) async {
    await _pump(tester);

    await tester.tap(find.widgetWithText(InkWell, 'Out 1'));
    await tester.pumpAndSettle();
    expect(_rowCount(tester), 1);

    await tester.tap(find.widgetWithText(InkWell, 'Out 1'));
    await tester.pumpAndSettle();
    expect(_rowCount(tester), 7);
  });

  // NOTE: there is deliberately no "the chips fit on one row" test here.
  // Widget tests render with a stand-in font whose every glyph is a full em
  // square, so "Maybe 1" measures ~97dp in a test and ~47dp in Baloo 2 on a
  // device. A layout assertion written here fails on chips that fit perfectly
  // well in the app. The real widths were measured from the shipped font
  // binary instead, and are recorded on _RsvpChip.
}

