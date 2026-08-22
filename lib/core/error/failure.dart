/// Typed failures. Repositories catch raw backend exceptions (PostgrestException,
/// AuthException, StorageException) and rethrow these. Controllers map them to
/// user-facing messages. A raw PostgrestException must never reach the UI.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

sealed class Failure implements Exception {
  const Failure(this.message);

  /// A human-readable, user-safe message.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Network / connectivity problems.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No connection. Check your network and try again.']);
}

/// Authentication problems (bad credentials, expired session, etc.).
final class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// A uniqueness conflict — e.g. the handle is already taken.
final class ConflictFailure extends Failure {
  const ConflictFailure(super.message);
}

/// The action was refused by the database (RLS, a guard trigger, a constraint).
/// This is the status FK, the last-organizer guard, etc.
final class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'You don\'t have permission to do that.']);
}

/// The requested thing doesn't exist (or isn't visible to you — by design we
/// cannot distinguish the two, and must not try to).
final class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'Not found.']);
}

/// Bad input the app should have caught (kept as a safety net).
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

/// Anything we didn't anticipate. Carries the original for logging.
final class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Something went wrong.', this.cause]);
  final Object? cause;
}

/// Map a raw thrown object to a typed [Failure]. Central so every repository
/// translates Postgres/Auth errors consistently.
Failure mapToFailure(Object error) {
  if (error is Failure) return error;

  if (error is AuthException) {
    return AuthFailure(error.message);
  }

  if (error is PostgrestException) {
    // SQLSTATE codes raised by our schema/guards.
    switch (error.code) {
      case '23505': // unique_violation
        // Every uniqueness conflict in the app lands here — a taken handle, a
        // duplicate membership, a repeated vote or reaction. Reporting them
        // all as "that handle is already taken" is actively misleading
        // (a second poll vote used to say exactly that), so key off the
        // constraint/column named in the error and fall back to something
        // honest and generic.
        final detail =
            '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
                .toLowerCase();
        if (detail.contains('nickname') ||
            detail.contains('tagline') ||
            detail.contains('handle')) {
          return const ConflictFailure('That handle is already taken.');
        }
        return const ConflictFailure('That has already been added.');
      case '23503': // foreign_key_violation — bad status/phase, missing ref
      case '23514': // check_violation — length checks, guard triggers
        return PermissionFailure(error.message);
      case '42501': // insufficient_privilege — RLS / SECURITY DEFINER guard
      case 'P0001': // raise_exception (our explicit raises)
        return PermissionFailure(error.message);
      case 'PGRST116': // no rows when one expected (.single())
        return const NotFoundFailure();
    }
    return UnknownFailure(error.message, error);
  }

  if (error is StorageException) {
    return UnknownFailure(error.message, error);
  }

  return UnknownFailure(error.toString(), error);
}
