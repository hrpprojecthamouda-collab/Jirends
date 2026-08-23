/// Incoming deep links -> go_router.
///
/// WHY THIS EXISTS, rather than `flutter_deeplinking_enabled` in the manifest:
/// `supabase_flutter` registers the `app_links` plugin to catch its own OAuth
/// callbacks, and that plugin CONSUMES the VIEW intent. Flutter's built-in deep
/// link handling therefore never sees the URL, the app cold-starts on its
/// default route, and the link looks like it did nothing. Confirmed from
/// logcat: `com.llfbandit.app_links: Handled intent ... jirends://...`.
///
/// So we listen to the same plugin supabase already pulled in - no new
/// dependency - and drive the router ourselves.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../routing/app_router.dart';

/// Translate an incoming URI into a route, or null if it is not one of ours.
///
/// Kept pure and separate from the plumbing so it can be tested without a
/// platform channel. Accepts both the custom scheme in use today and the https
/// form that App Links will deliver once a domain is verified - they carry the
/// same path, which is the whole point of the host being `jirends.app` in both.
String? routeForDeepLink(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.length == 2 && segments.first == 'join') {
    final token = segments[1];
    if (token.isEmpty) return null;
    return AppRoutes.joinEvent(token);
  }
  return null;
}

/// Starts listening once, for the life of the app.
class DeepLinkService {
  DeepLinkService(this._ref);
  final Ref _ref;

  StreamSubscription<Uri>? _sub;
  final _links = AppLinks();

  Future<void> start() async {
    // The link that cold-started the app, if any.
    final initial = await _links.getInitialLink();
    if (initial != null) _go(initial);

    // ...and any that arrive while it is already running.
    _sub = _links.uriLinkStream.listen(_go);
  }

  void _go(Uri uri) {
    final route = routeForDeepLink(uri);
    // Not ours (a Supabase auth callback, for instance) - leave it alone.
    if (route == null) return;
    _ref.read(routerProvider).go(route);
  }

  void dispose() => _sub?.cancel();
}

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final service = DeepLinkService(ref);
  ref.onDispose(service.dispose);
  return service;
});
