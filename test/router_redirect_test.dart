/// The auth / onboarding redirect guard.
///
/// The bug these were written for: signing in flashed the nickname+tagline
/// onboarding screen at users who already had a handle. Riverpod keeps the
/// PREVIOUS value while a FutureProvider re-fetches, so at sign-in the guard
/// was reading the signed-out profile (null), concluding "no handle", and
/// routing to onboarding until the real profile landed a moment later.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jirends/features/auth/data/profile.dart';
import 'package:jirends/routing/app_router.dart';

const _me = 'user-1';
const _settled = Profile(id: _me, nickname: 'Sparrow', tagline: 'TheCrew');
const _noHandle = Profile(id: _me);

/// The state a FutureProvider is really in midway through a re-fetch:
/// AsyncLoading that has KEPT the previous value.
///
/// Driven through a live ProviderContainer rather than hand-built, because
/// that retention is the exact Riverpod behaviour the bug came from — a
/// hand-made AsyncValue would only be testing my belief about it.
Future<AsyncValue<Profile?>> _reloading(Profile? previous) async {
  var settled = false;
  final pending = Completer<Profile?>();
  final provider = FutureProvider<Profile?>((ref) {
    if (settled) return pending.future; // second run never completes
    settled = true;
    return Future.value(previous);
  });

  final container = ProviderContainer();
  addTearDown(container.dispose);

  await container.read(provider.future); // settle on `previous`
  container.invalidate(provider); // start re-fetching
  return container.read(provider);
}

void main() {
  group('signed out', () {
    test('anything but the auth pages goes to sign-in', () {
      expect(
        redirectFor(
            userId: null, profile: const AsyncData(null), location: '/'),
        '/sign-in',
      );
    });

    test('the auth pages are left alone', () {
      expect(
        redirectFor(
            userId: null, profile: const AsyncData(null), location: '/sign-up'),
        isNull,
      );
    });
  });

  group('signing in', () {
    test('THE BUG: a stale signed-out profile must not mean "no handle"',
        () async {
      // The moment after sign-in: session is live, myProfileProvider is
      // re-running, and the value it still holds is the signed-out null.
      final reloading = await _reloading(null);
      expect(reloading.isLoading, isTrue);
      expect(reloading.hasValue, isTrue,
          reason: 'Riverpod keeps the old value — the trap the guard fell into');

      final where = redirectFor(
        userId: _me,
        profile: reloading,
        location: '/sign-in',
      );
      expect(where, '/splash',
          reason: 'wait for the real profile; do not guess onboarding');
      expect(where, isNot('/onboarding'));
    });

    test('a stale OTHER user profile is not trusted either', () async {
      // Account switching: the previous user's profile is still in hand.
      const other = Profile(id: 'someone-else', nickname: 'A', tagline: 'B');
      expect(
        redirectFor(
            userId: _me, profile: await _reloading(other), location: '/'),
        '/splash',
      );
    });

    test('cold start with nothing loaded holds on the splash', () {
      expect(
        redirectFor(
            userId: _me, profile: const AsyncLoading(), location: '/'),
        '/splash',
      );
      expect(
        redirectFor(
            userId: _me, profile: const AsyncLoading(), location: '/splash'),
        isNull,
      );
    });
  });

  group('signed in', () {
    test('a handle sends you home from splash, auth and onboarding', () {
      for (final from in ['/splash', '/sign-in', '/onboarding']) {
        expect(
          redirectFor(
              userId: _me, profile: const AsyncData(_settled), location: from),
          '/',
          reason: from,
        );
      }
    });

    test('a handle leaves ordinary pages alone', () {
      expect(
        redirectFor(
            userId: _me,
            profile: const AsyncData(_settled),
            location: '/events'),
        isNull,
      );
    });

    test('a real profile without a handle still onboards', () {
      expect(
        redirectFor(
            userId: _me, profile: const AsyncData(_noHandle), location: '/'),
        '/onboarding',
      );
    });

    test('genuinely new user, settled with no row, onboards', () {
      expect(
        redirectFor(
            userId: _me, profile: const AsyncData(null), location: '/'),
        '/onboarding',
      );
    });

    test('a background refresh does NOT bounce you to the splash', () async {
      // Uploading an avatar invalidates myProfileProvider mid-session. The
      // retained value is this user's own, so the guard must sit still.
      expect(
        redirectFor(
            userId: _me,
            profile: await _reloading(_settled),
            location: '/events'),
        isNull,
      );
    });
  });
}
