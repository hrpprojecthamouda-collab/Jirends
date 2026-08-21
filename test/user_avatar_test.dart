/// UserAvatar is the single place that decides photo-vs-initials, and it is on
/// screen in every member list, friend list and comment thread — so a wrong
/// answer here is wrong everywhere at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jirends/features/auth/data/profile.dart';
import 'package:jirends/features/profile/presentation/user_avatar.dart';

const _withPhoto = Profile(
  id: 'u1',
  nickname: 'Sparrow',
  tagline: 'TheCrew',
  avatarUrl: 'https://example.test/avatars/u1/abc.png',
);

const _noPhoto = Profile(id: 'u2', nickname: 'Sparrow', tagline: 'TheCrew');

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('no photo falls back to initials', (tester) async {
    await tester.pumpWidget(_host(const UserAvatar(profile: _noPhoto)));
    expect(find.text('ST'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a null profile still renders a circle, not a crash',
      (tester) async {
    await tester.pumpWidget(_host(const UserAvatar(profile: null)));
    expect(find.text('?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty avatar_url counts as no photo', (tester) async {
    // The column is nullable, but a cleared photo could also be written as ''
    // by some other client; both have to mean "show initials".
    await tester.pumpWidget(
      _host(const UserAvatar(profile: Profile(id: 'u3', avatarUrl: ''))),
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a photo url is rendered as an image', (tester) async {
    await tester.pumpWidget(_host(const UserAvatar(profile: _withPhoto)));
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('an unreachable photo falls back to initials, silently',
      (tester) async {
    // Network images fail in widget tests (the test HttpClient returns 400),
    // which is exactly the offline / deleted-object case.
    await tester.pumpWidget(_host(const UserAvatar(profile: _withPhoto)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('ST'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'a missing photo is normal, not an error to throw');
  });

  testWidgets('the circle honours its radius', (tester) async {
    await tester.pumpWidget(_host(const UserAvatar(profile: _noPhoto, radius: 16)));
    expect(tester.getSize(find.byType(UserAvatar)), const Size(32, 32));
  });

  testWidgets('stays a circle in an app bar, which constrains it tightly',
      (tester) async {
    // Regression: AppBar.leading forces a tight ~56px box on its child, and a
    // SizedBox cannot shrink out of tight constraints — the avatar stretched
    // into a toolbar-sized oval until the button wrapped it in a Center.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          leading: const Center(
            child: UserAvatar(profile: _noPhoto, radius: 16),
          ),
        ),
      ),
    ));

    final size = tester.getSize(find.byType(UserAvatar));
    expect(size, const Size(32, 32));
    expect(size.width, size.height, reason: 'a circle, not an oval');
  });
}
