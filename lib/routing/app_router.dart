/// App router. The redirect guard is where the auth + onboarding flow lives:
///
///   no session            -> /sign-in
///   session, no handle    -> /onboarding
///   session, has handle   -> the app shell (nav rail + branches)
///
/// Signed-in users land in a StatefulShellRoute: a bottom nav bar with four
/// branches (Home, Events, Friends, Groups), each keeping its own nav stack,
/// plus top-level /profile and /settings overlays.
///
/// Event detail (/events/:id and below) is deliberately pushed on the ROOT
/// navigator so it renders above the shell — an open event gets the full
/// screen with no bottom nav bar.
///
/// Visibility of *events* is NOT decided here — that is the database's job
/// (the cardinal rule). This guard only gates auth and the one-time handle
/// onboarding step.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/supabase/supabase_providers.dart';
import '../features/auth/data/profile.dart';
import '../features/auth/data/profile_repository.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/auth/presentation/sign_up_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/events/data/comment.dart';
import '../features/events/presentation/events_list_screen.dart';
import '../features/events/presentation/create_event_screen.dart';
import '../features/events/presentation/event_detail_screen.dart';
import '../features/events/presentation/join_event_screen.dart';
import '../features/events/presentation/discussion_screen.dart';
import '../features/friends/presentation/friends_screen.dart';
import '../features/groups/presentation/groups_screen.dart';
import '../features/groups/presentation/group_detail_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/home/presentation/splash_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/shell/presentation/app_shell.dart';

class AppRoutes {
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const onboarding = '/onboarding';
  static const splash = '/splash';

  // Shell branches.
  static const home = '/';
  static const events = '/events';
  static const friends = '/friends';
  static const groups = '/groups';

  // Overlays (top-level, not branches).
  static const profile = '/profile';
  static const settings = '/settings';

  static const createEvent = '/events/new';

  /// Redeeming an invite link. Path: /join/:token
  static String joinEvent(String token) => '/join/$token';
  static const joinPrefix = '/join/';

  /// Detail route for one event. Path: /events/:id
  static String eventDetail(String id) => '/events/$id';

  /// Discussion route for one comment. Path: /events/:id/discussion/:rootId
  /// (pass the root Comment via extra to avoid a re-fetch).
  static String discussion(String eventId, String rootId) =>
      '/events/$eventId/discussion/$rootId';

  /// Detail route within the Groups branch.
  static String groupDetail(String id) => '/groups/group/$id';
}

final _rootKey = GlobalKey<NavigatorState>();

/// Where the user belongs, given the session and what we currently know about
/// their profile. Pure and separate from GoRouter so it can be tested directly
/// — the states that matter here are transient and near-impossible to catch by
/// hand in a running app.
///
/// The subtle case is [profile] being AsyncLoading *with a stale value*.
/// Riverpod keeps the previous value across a re-fetch, so `hasValue` stays
/// true while myProfileProvider re-runs for the new session. Trusting it meant
/// that at sign-in the guard read the SIGNED-OUT profile (null), concluded
/// "no handle" and flashed the onboarding screen at returning users until the
/// real profile arrived. So the question is not "do we have a profile" but
/// "do we have THIS user's profile".
///
/// This gates auth and the one-time handle step only. Event visibility is the
/// database's job (the cardinal rule) and is never decided here.
@visibleForTesting
String? redirectFor({
  required String? userId,
  required AsyncValue<Profile?> profile,
  required String location,
  String? pendingInvite,
}) {
  final loggingIn =
      location == AppRoutes.signIn || location == AppRoutes.signUp;
  final joining = location.startsWith(AppRoutes.joinPrefix);

  // 1. No session -> must authenticate. /join is allowed through: the screen
  //    itself stashes the token and offers to sign in, which is the only way
  //    the token survives the round trip. Bouncing straight to /sign-in would
  //    swallow it and the link would appear to do nothing.
  if (userId == null) {
    return (loggingIn || joining) ? null : AppRoutes.signIn;
  }

  // 2. Signed in. Is the profile we are holding actually this user's?
  final loaded = profile.value;
  final knowsThisUser = loaded != null && loaded.id == userId;

  if (!knowsThisUser) {
    // Still fetching (cold start, or the swap right after signing in): we
    // cannot tell onboarding from home yet, so wait on the splash rather than
    // guess. Guessing is what caused the flash.
    if (profile.isLoading) {
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    }
    // Settled with no profile for this user: genuinely new, so onboard them.
    // (An errored fetch lands here too — onboarding is recoverable, whereas
    // holding on the splash forever is not.)
    return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
  }

  final onOnboarding = location == AppRoutes.onboarding;

  // 3. Signed in, no handle yet -> onboarding.
  if (!loaded.hasHandle) {
    return onOnboarding ? null : AppRoutes.onboarding;
  }

  // 4. Signed in with a handle, and an invite was stashed before signing in:
  //    resume it. This is what makes "tap link -> sign in -> land in the
  //    event" work rather than dumping the user on Home having lost the token.
  if (pendingInvite != null && !joining) {
    return AppRoutes.joinEvent(pendingInvite);
  }

  // 5. Fully set up -> keep them out of auth/onboarding/splash pages.
  if (loggingIn || onOnboarding || location == AppRoutes.splash) {
    return AppRoutes.home;
  }
  return null;
}

/// A token captured from a link that arrived before the user was signed in.
/// Set by the join screen, consumed by [redirectFor] and cleared once the join
/// screen has it in hand. In memory only: if the app is killed mid-sign-in the
/// user taps the link again, which is a fair trade for not persisting a
/// membership-granting token to disk.
class PendingInvite extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? token) => state = token;
}

final pendingInviteProvider =
    NotifierProvider<PendingInvite, String?>(PendingInvite.new);

final routerProvider = Provider<GoRouter>((ref) {
  // Rebuild routing decisions whenever auth or the profile changes.
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      userId: ref.read(currentSessionProvider)?.user.id,
      profile: ref.read(myProfileProvider),
      location: state.matchedLocation,
      pendingInvite: ref.read(pendingInviteProvider),
    ),
    routes: [
      // ── Auth / onboarding / splash (outside the shell) ──────────────────
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: AppRoutes.signUp, builder: (_, _) => const SignUpScreen()),
      GoRoute(
          path: AppRoutes.onboarding,
          builder: (_, _) => const OnboardingScreen()),

      // Invite links. Top-level (not in the shell) and reachable while signed
      // OUT — the screen stashes the token and offers to sign in, which is how
      // the token survives the round trip.
      GoRoute(
        path: '/join/:token',
        builder: (_, state) =>
            JoinEventScreen(token: state.pathParameters['token']!),
      ),

      // ── Profile + Settings: top-level overlays, not branches ───────────
      GoRoute(
          path: AppRoutes.profile, builder: (_, _) => const ProfileScreen()),
      GoRoute(
          path: AppRoutes.settings, builder: (_, _) => const SettingsScreen()),

      // ── The signed-in app shell: bottom nav + four branches ────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // Home
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
          ]),
          // Events (+ create / detail as pushes within this branch)
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.events,
              builder: (_, _) => const EventsListScreen(),
              routes: [
                GoRoute(
                    path: 'new',
                    builder: (_, _) => const CreateEventScreen()),
                // Opening an event takes over the whole screen: pushing it on
                // the ROOT navigator puts it above the shell, so the bottom
                // nav bar is absent (not merely hidden) while you're inside
                // an event. Back still returns to the Events list.
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) =>
                      EventDetailScreen(eventId: state.pathParameters['id']!),
                  routes: [
                    GoRoute(
                      path: 'discussion/:rootId',
                      parentNavigatorKey: _rootKey,
                      builder: (context, state) => DiscussionScreen(
                        eventId: state.pathParameters['id']!,
                        rootId: state.pathParameters['rootId']!,
                        rootComment: state.extra as Comment?,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          // Friends
          StatefulShellBranch(routes: [
            GoRoute(
                path: AppRoutes.friends,
                builder: (_, _) => const FriendsScreen()),
          ]),
          // Groups (+ group detail as a push within this branch)
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.groups,
              builder: (_, _) => const GroupsScreen(),
              routes: [
                GoRoute(
                  path: 'group/:id',
                  builder: (context, state) =>
                      GroupDetailScreen(groupId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod provider changes to a [Listenable] for go_router's
/// refreshListenable.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    _subs = [
      ref.listen(currentSessionProvider, (prev, next) => notifyListeners()),
      ref.listen(myProfileProvider, (prev, next) => notifyListeners()),
    ];
  }
  late final List<ProviderSubscription> _subs;

  @override
  void dispose() {
    for (final s in _subs) {
      s.close();
    }
    super.dispose();
  }
}
