/// OnboardingController — sets the user's handle (nickname#tagline). On success
/// it invalidates myProfileProvider so the router's gate re-evaluates and lets
/// the user into the app.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/profile.dart';
import '../../auth/data/profile_repository.dart';

class OnboardingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Validates locally, then persists. Throws nothing; result lands in [state].
  /// Returns true on success.
  Future<bool> setHandle({required String nickname, required String tagline}) async {
    final n = nickname.trim();
    final t = tagline.trim();

    // Client-side guard mirrors the DB CHECK constraints for a fast, friendly
    // error. The DB remains the real validator.
    final localError = _validate(n, t);
    if (localError != null) {
      state = AsyncError(localError, StackTrace.current);
      return false;
    }

    state = const AsyncLoading();
    final result = await AsyncValue.guard<Profile>(
      () => ref.read(profileRepositoryProvider).setHandle(nickname: n, tagline: t),
    );
    state = result.hasError ? AsyncError(result.error!, result.stackTrace!) : const AsyncData(null);

    if (!result.hasError) {
      // Re-fetch the profile so the onboarding gate sees the handle.
      ref.invalidate(myProfileProvider);
      return true;
    }
    return false;
  }

  Object? _validate(String nickname, String tagline) {
    bool okLen(String s) => s.length >= 2 && s.length <= 24;
    if (!okLen(nickname)) return 'Nickname must be 2–24 characters.';
    if (!okLen(tagline)) return 'Tagline must be 2–24 characters.';
    if (nickname.contains('#') || tagline.contains('#')) {
      return 'Nickname and tagline cannot contain “#”.';
    }
    return null;
  }
}

final onboardingControllerProvider = AsyncNotifierProvider<OnboardingController, void>(
  OnboardingController.new,
);
