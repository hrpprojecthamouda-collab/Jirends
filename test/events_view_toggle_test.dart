/// The List / Agenda switch moved out of a full-width row under the title and
/// into the app bar as two icons. These pin the part that is easy to break in
/// that move: that both icons are still reachable and still switch the body.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jirends/core/i18n/fallback_material_localizations.dart';
import 'package:jirends/core/supabase/supabase_providers.dart';
import 'package:jirends/core/theme/app_palette.dart';
import 'package:jirends/core/theme/app_theme.dart';
import 'package:jirends/features/events/application/event_list_controller.dart';
import 'package:jirends/features/events/data/event.dart';
import 'package:jirends/features/events/presentation/events_list_screen.dart';
import 'package:jirends/features/events/presentation/widgets/agenda_view.dart';
import 'package:jirends/l10n/app_localizations.dart';

final _now = DateTime(2026, 8, 20, 19, 0);

final _events = [
  Event(
    id: 'e1',
    title: 'Apero',
    eventType: EventType.dinner,
    status: 'confirmed',
    startsAt: _now.add(const Duration(days: 2)),
    createdBy: 'me',
    createdAt: _now,
    updatedAt: _now,
  ),
];

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      eventListProvider.overrideWith((ref) => Stream.value(_events)),
      eventMemberCountsProvider.overrideWith((ref) => Stream.value(const {})),
    ],
    child: MaterialApp(
      theme: AppTheme.of(kDefaultPalette),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...tnAwareFrameworkDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const EventsListScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('both view icons sit in the app bar', (tester) async {
    await _pump(tester);

    final appBar = find.byType(AppBar);
    expect(
      find.descendant(
          of: appBar, matching: find.byIcon(Icons.view_list_outlined)),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: appBar, matching: find.byIcon(Icons.calendar_month_outlined)),
      findsOneWidget,
    );
  });

  testWidgets('the toggle no longer occupies a row of its own', (tester) async {
    await _pump(tester);
    // The old labelled control. Its whole point was that it took a full row.
    expect(find.byType(SegmentedButton<Object?>), findsNothing);
    expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
  });

  testWidgets('tapping the agenda icon switches the body', (tester) async {
    await _pump(tester);
    expect(find.byType(AgendaView), findsNothing);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(AgendaView), findsOneWidget);

    await tester.tap(find.byIcon(Icons.view_list_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(AgendaView), findsNothing);
  });
}
