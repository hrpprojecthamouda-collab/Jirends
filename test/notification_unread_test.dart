/// Unread notifications: the badge counts them, the sheet highlights them, and
/// opening the sheet clears them.
///
/// The trap this guards: the sheet marks everything read on open, so the live
/// `isUnread` flag is already false by the time the first frame paints. The
/// highlight has to come from a snapshot taken BEFORE the mark, or "what's
/// new" is invisible at exactly the moment the user opened the sheet to see it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jirends/core/i18n/fallback_material_localizations.dart';
import 'package:jirends/core/theme/app_palette.dart';
import 'package:jirends/core/theme/app_theme.dart';
import 'package:jirends/features/auth/data/profile.dart';
import 'package:jirends/features/notifications/application/notification_controller.dart';
import 'package:jirends/features/notifications/data/notification.dart';
import 'package:jirends/features/notifications/data/notification_repository.dart';
import 'package:jirends/features/notifications/presentation/widgets/notification_bell_button.dart';
import 'package:jirends/l10n/app_localizations.dart';

final _now = DateTime(2026, 8, 21, 12);

AppNotification _n(String id, {required bool unread}) => AppNotification(
      id: id,
      recipientId: 'me',
      actorId: 'moez',
      kind: 'friend_added',
      readAt: unread ? null : _now,
      createdAt: _now,
      actor: const Profile(id: 'moez', nickname: 'moez', tagline: 'crew'),
    );

/// Drives the notification stream directly. `myNotificationsProvider` reaches
/// currentSessionProvider -> the Supabase singleton, which does not exist in a
/// widget test, so the provider is overridden rather than the repository alone.
///
/// markAllRead flips the rows to read and pushes them, which is exactly what
/// the real stream does — and what used to wipe the highlight.
class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository(this.rows);
  List<AppNotification> rows;
  int markAllReadCalls = 0;
  final controller = StreamController<List<AppNotification>>.broadcast();

  @override
  Future<void> markAllRead() async {
    markAllReadCalls++;
    rows = [for (final n in rows) n.copyWith(readAt: _now)];
    controller.add(rows);
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not used by this test');
}

Future<_FakeNotificationRepository> _pump(
  WidgetTester tester,
  List<AppNotification> initial,
) async {
  final repo = _FakeNotificationRepository(initial);
  addTearDown(repo.controller.close);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      notificationRepositoryProvider.overrideWithValue(repo),
      myNotificationsProvider.overrideWith(
        (ref) async* {
          yield repo.rows;
          yield* repo.controller.stream;
        },
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.of(kDefaultPalette),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...tnAwareFrameworkDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Center(child: NotificationBellButton())),
    ),
  ));
  await tester.pumpAndSettle();
  return repo;
}

/// How many rows are marked unread, counted by the dot's semantics label
/// rather than its shape — CircleAvatar also builds a circular Container, so a
/// shape-based finder counts every leading avatar too.
/// RegExp, not an exact string: ListTile merges its descendants into one
/// semantics node, so the dot's label arrives as part of the row's full label
/// ("...added you, 12:00, Unread") rather than on its own.
int _dotCount(WidgetTester tester) =>
    tester.widgetList(find.bySemanticsLabel(RegExp('Unread'))).length;

void main() {
  testWidgets('the badge counts only unread', (tester) async {
    await _pump(tester, [
      _n('a', unread: true),
      _n('b', unread: true),
      _n('c', unread: false),
    ]);

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('no badge when everything has been read', (tester) async {
    await _pump(tester, [_n('a', unread: false)]);

    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isFalse);
  });

  testWidgets('THE TRAP: unread stay highlighted after the mark-read lands',
      (tester) async {
    final handle = tester.ensureSemantics();

    final repo = await _pump(tester, [
      _n('a', unread: true),
      _n('b', unread: true),
      _n('c', unread: false),
    ]);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // The rows are read in the database by now...
    expect(repo.markAllReadCalls, 1);
    // ...but the two that WERE new still carry their dot.
    expect(_dotCount(tester), 2);
    handle.dispose();
  });

  testWidgets('opening the sheet clears the badge', (tester) async {
    await _pump(tester, [_n('a', unread: true)]);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // The badge is behind the sheet but still in the tree — and now empty.
    expect(find.text('1'), findsNothing);
  });

  testWidgets('an all-read list marks nothing and highlights nothing',
      (tester) async {
    final handle = tester.ensureSemantics();

    final repo = await _pump(tester, [_n('a', unread: false)]);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(repo.markAllReadCalls, 0, reason: 'no pointless write');
    expect(_dotCount(tester), 0);
    handle.dispose();
  });
}
