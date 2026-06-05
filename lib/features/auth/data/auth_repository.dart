/// AuthRepository — the only place auth calls to Supabase happen for sign
/// up / in / out. Throws typed [Failure]s; never lets a raw AuthException out.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';

class AuthRepository {
  AuthRepository(this._auth);
  final GoTrueClient _auth;

  Session? get currentSession => _auth.currentSession;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithPassword(email: email, password: password);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Sign up. On a project with email confirmation ON, this returns with no
  /// session and the user must confirm via email first. We surface that state
  /// to the controller via the returned [AuthResponse].
  Future<AuthResponse> signUp({required String email, required String password}) async {
    try {
      return await _auth.signUp(email: email, password: password);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(goTrueClientProvider));
});
