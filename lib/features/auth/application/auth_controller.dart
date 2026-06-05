/// AuthController — orchestrates sign in / up / out and exposes an AsyncValue
/// the UI binds to for loading/error states. Maps typed [Failure]s to messages.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../data/auth_repository.dart';

/// Result of a sign-up attempt, so the screen can tell the user whether they
/// need to confirm their email before signing in.
enum SignUpOutcome { signedIn, needsEmailConfirmation }

class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // No initial async work; the controller is action-oriented.
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.signIn(email: email, password: password));
  }

  /// Returns the outcome so the UI can route or show "check your email".
  /// Throws nothing — errors land in [state].
  Future<SignUpOutcome?> signUp({required String email, required String password}) async {
    state = const AsyncLoading();
    SignUpOutcome? outcome;
    state = await AsyncValue.guard(() async {
      final res = await _repo.signUp(email: email, password: password);
      outcome = res.session != null
          ? SignUpOutcome.signedIn
          : SignUpOutcome.needsEmailConfirmation;
    });
    return state.hasError ? null : outcome;
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.signOut);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);

/// Turn a thrown error (always a [Failure] from our repos) into a message.
String messageForError(Object error) =>
    error is Failure ? error.message : 'Something went wrong.';
