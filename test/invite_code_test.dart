/// Pulling an invite token out of whatever the user pasted.
///
/// This exists because a jirends:// link is not tappable in messaging apps —
/// they linkify http/https only, and an in-app browser handed a custom scheme
/// reports "webpage not available". So people copy the message instead, and
/// what lands in the field is unpredictable: a bare code, a link, or the whole
/// three-line share text.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jirends/features/events/presentation/widgets/join_with_code_sheet.dart';

// 22 url-safe base64 chars, the shape create_event_invite emits.
const _token = 'Xk9-2QmPz4aB3cD5eF7gH_';

void main() {
  test('a bare code', () {
    expect(extractToken(_token), _token);
  });

  test('surrounding whitespace and newlines are tolerated', () {
    expect(extractToken('  $_token \n'), _token);
  });

  test('the custom-scheme link', () {
    expect(extractToken('jirends://jirends.app/join/$_token'), _token);
  });

  test('the https link an App Link will use later', () {
    expect(extractToken('https://jirends.app/join/$_token'), _token);
  });

  test('THE REAL CASE: the whole shared message pasted in', () {
    // Exactly what Share puts on the clipboard.
    final pasted = 'kharja khfifa on Jirends\n'
        'Join with code: $_token\n'
        'jirends://jirends.app/join/$_token';
    expect(extractToken(pasted), _token);
  });

  test('a message with the code but no link', () {
    expect(extractToken('hey join us! code $_token thanks'), _token);
  });

  test('plain prose yields nothing', () {
    expect(extractToken('are you coming tonight or not'), isNull);
    expect(extractToken(''), isNull);
    expect(extractToken('   '), isNull);
  });

  test('a too-short code is rejected rather than sent to the server', () {
    expect(extractToken('abc123'), isNull);
  });

  test('a /join link with a malformed token is rejected', () {
    expect(extractToken('https://jirends.app/join/short'), isNull);
  });

  test('an unrelated URL is not mined for look-alike segments', () {
    // A long path segment in someone else's link must not be taken for a code.
    expect(extractToken('https://example.com/some/other/path'), isNull);
  });
}
