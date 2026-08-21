import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jirends/core/error/failure.dart';

void main() {
  group('unique-violation messages are specific', () {
    test('a taken handle still says so', () {
      final f = mapToFailure(PostgrestException(
        message: 'duplicate key value violates unique constraint '
            '"profiles_nickname_tagline_key"',
        code: '23505',
      ));
      expect(f, isA<ConflictFailure>());
      expect(f.message, contains('handle'));
    });

    test('a duplicate vote does NOT claim the handle is taken', () {
      final f = mapToFailure(PostgrestException(
        message: 'duplicate key value violates unique constraint '
            '"poll_votes_poll_id_user_id_key"',
        code: '23505',
      ));
      expect(f, isA<ConflictFailure>());
      expect(f.message.toLowerCase(), isNot(contains('handle')),
          reason: 'this was the bug: every 23505 blamed the handle');
    });

    test('a duplicate reaction does not either', () {
      final f = mapToFailure(PostgrestException(
        message: 'duplicate key value violates unique constraint '
            '"reactions_unique_on_comment"',
        code: '23505',
      ));
      expect(f.message.toLowerCase(), isNot(contains('handle')));
    });
  });
}
