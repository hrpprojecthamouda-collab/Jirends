/// Signing out has no undo short of typing your password again, so the one
/// behaviour worth pinning is that a single tap never does it on its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jirends/core/i18n/fallback_material_localizations.dart';
import 'package:jirends/core/theme/app_palette.dart';
import 'package:jirends/core/theme/app_theme.dart';
import 'package:jirends/features/auth/data/auth_repository.dart';
import 'package:jirends/features/auth/presentation/widgets/sign_out_tile.dart';
import 'package:jirends/l10n/app_localizations.dart';

/// Records sign-out calls instead of talking to Supabase. [failure] makes the
/// call throw, which is the case that used to fail silently.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.failure});
  final Object? failure;
  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (failure != null) throw failure!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used by this test');
}

Future<_FakeAuthRepository> _pump(WidgetTester tester, {Object? failure}) async {
  final repo = _FakeAuthRepository(failure: failure);
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: AppTheme.of(kDefaultPalette),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...tnAwareFrameworkDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SignOutTile()),
    ),
  ));
  return repo;
}

void main() {
  testWidgets('tapping the row asks before it signs you out', (tester) async {
    final repo = await _pump(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repo.signOutCalls, 0, reason: 'nothing has been confirmed yet');
  });

  testWidgets('cancelling leaves the session alone', (tester) async {
    final repo = await _pump(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.signOutCalls, 0);
  });

  testWidgets('confirming signs out exactly once', (tester) async {
    final repo = await _pump(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    // The dialog's confirm button carries the same label as the row.
    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();

    expect(repo.signOutCalls, 1);
  });

  testWidgets('a failed sign-out says so instead of doing nothing',
      (tester) async {
    await _pump(tester, failure: Exception('offline'));

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
