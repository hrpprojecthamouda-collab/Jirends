/// Adding a friend to an event, from the attendees panel.
///
/// The bug: the picker built its candidate list from
/// `ref.read(friendListProvider).value ?? const []`, which reads whatever the
/// provider holds AT THAT INSTANT. Riverpod 3 auto-disposes a provider nothing
/// is listening to, so unless another screen was holding friendListProvider
/// open, that read found AsyncLoading with no value and the picker was built
/// from an empty list. Visiting the Friends screen kept it alive, which is why
/// the second attempt worked and the bug looked random.
///
/// Pickers now take a one-shot snapshot from the repository, so the fetch here
/// resolves on a delay to stand in for a real round trip.
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
import 'package:jirends/features/friends/data/friend_repository.dart';
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

Profile _p(String id) => Profile(id: id, nickname: id, tagline: 'crew');

/// You are the organizer, and 'ana' is already in the event.
final _roster = [
  EventMember(
    userId: 'me',
    role: MemberRole.organizer,
    rsvp: RsvpStatus.going,
    profile: _p('me'),
  ),
  EventMember(
    userId: 'ana',
    role: MemberRole.member,
    rsvp: RsvpStatus.pending,
    profile: _p('ana'),
  ),
];

/// Four friends. 'ana' is already a member, so three are addable.
final _friends = [_p('ana'), _p('bob'), _p('cyd'), _p('dee')];

/// Stands in for the network: answers after [delay], or throws if [failure].
class _FakeFriendRepository implements FriendRepository {
  _FakeFriendRepository({this.delay = Duration.zero, this.failure});
  final Duration delay;
  final Object? failure;

  @override
  Future<List<Profile>> fetchFriends() async {
    await Future<void>.delayed(delay);
    if (failure != null) throw failure!;
    return _friends;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not used by this test');
}

Future<void> _pump(
  WidgetTester tester, {
  Duration friendsArriveAfter = Duration.zero,
  Object? failure,
}) async {
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      eventMembersProvider(_event.id)
          .overrideWith((ref) => Stream.value(_roster)),
      memberConflictsProvider(_event.id)
          .overrideWith((ref) async => const <String, bool>{}),
      friendRepositoryProvider.overrideWithValue(
        _FakeFriendRepository(delay: friendsArriveAfter, failure: failure),
      ),
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
  await tester.pump();
}

/// Text inside the picker sheet specifically. The roster behind it lists the
/// same handles, so an unscoped finder would happily match a member row.
Finder _inPicker(String handle) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(handle),
    );

/// FAB -> "Add a friend" in the menu -> the picker.
Future<void> _openFriendPicker(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton).first);
  await tester.pumpAndSettle();
  // The menu sheet and the FAB share the label; the sheet's is the ListTile.
  await tester.tap(find.widgetWithText(ListTile, 'Add a friend'));
  // Two settles: the first closes the menu sheet, and only then does the
  // awaited friend list resolve and push the picker.
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('THE BUG: a cold friend list still fills the picker',
      (tester) async {
    // Nothing has subscribed friendListProvider — no Friends screen visited.
    await _pump(tester, friendsArriveAfter: const Duration(milliseconds: 300));
    await _openFriendPicker(tester);

    expect(_inPicker('bob#crew'), findsOneWidget);
    expect(_inPicker('cyd#crew'), findsOneWidget);
    expect(_inPicker('dee#crew'), findsOneWidget);
  });

  testWidgets('people already in the event are not offered again',
      (tester) async {
    await _pump(tester, friendsArriveAfter: const Duration(milliseconds: 300));
    await _openFriendPicker(tester);

    // 'ana' is a member already, so she is not offered as a candidate — even
    // though her name is on screen, on the roster behind the sheet.
    expect(_inPicker('ana#crew'), findsNothing);
    expect(_inPicker('bob#crew'), findsOneWidget);
  });

  testWidgets('a warm friend list opens the picker without a wait',
      (tester) async {
    await _pump(tester);
    await _openFriendPicker(tester);

    expect(_inPicker('bob#crew'), findsOneWidget);
  });

  testWidgets('a failing fetch reports instead of opening an empty picker',
      (tester) async {
    await _pump(tester, failure: Exception('offline'));
    await _openFriendPicker(tester);

    // A snackbar, not a picker claiming you have no friends to add.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(_inPicker('bob#crew'), findsNothing);
  });
}

