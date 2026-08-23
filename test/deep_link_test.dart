/// Mapping an incoming URL to a route.
///
/// Kept as a pure function so it can be tested without a platform channel —
/// the plumbing around it (app_links) cannot be, and that plumbing is exactly
/// why this exists: supabase_flutter's copy of app_links swallows the VIEW
/// intent, so Flutter's built-in deep linking never fires.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jirends/core/util/deep_links.dart';

void main() {
  test('the custom scheme in use today', () {
    expect(routeForDeepLink(Uri.parse('jirends://jirends.app/join/abc123')),
        '/join/abc123');
  });

  test('the https form an App Link will deliver later', () {
    // Same host and path on purpose: switching schemes must not change routing.
    expect(routeForDeepLink(Uri.parse('https://jirends.app/join/abc123')),
        '/join/abc123');
  });

  test('a token with url-safe base64 characters survives', () {
    // create_event_invite emits base64 translated to -_ , so both must pass
    // through untouched.
    const token = 'aB3-_xY9zQ1w2E4r5T6y7U';
    expect(routeForDeepLink(Uri.parse('jirends://jirends.app/join/$token')),
        '/join/$token');
  });

  test('a Supabase auth callback is left alone', () {
    // supabase_flutter shares this plugin; grabbing its callbacks would break
    // sign-in.
    expect(
        routeForDeepLink(Uri.parse('jirends://jirends.app/login-callback')),
        isNull);
  });

  test('an empty or missing token is not a route', () {
    expect(routeForDeepLink(Uri.parse('jirends://jirends.app/join/')), isNull);
    expect(routeForDeepLink(Uri.parse('jirends://jirends.app/join')), isNull);
  });

  test('extra path segments are not a join link', () {
    expect(
        routeForDeepLink(Uri.parse('jirends://jirends.app/join/abc/extra')),
        isNull);
  });
}
