/// App router. The redirect guard is where the auth + onboarding flow lives:
///
///   no session            -> /sign-in
///   session, no handle    -> /onboarding
///   session, has handle   -> the app shell (nav rail + branches)
///
/// Signed-in users land in a StatefulShellRoute: a left nav rail with four
/// branches (Home, Events, Friends, Groups), each keeping its own nav stack,
/// plus a top-level /settings overlay reached from the rail's gear.
///
/// Visibility of *events* is NOT decided here — that is the database's job
/// (the cardinal rule). This guard only gates auth and the one-time handle
/// onboarding step.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/supabase/supabase_providers.dart';
import '../features/auth/data/profile_repository.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/auth/presentation/sign_up_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/events/presentation/events_list_screen.dart';
import '../features/events/presentation/create_event_screen.dart';
import '../features/events/presentation/event_detail_screen.dart';
import '../features/events/presentation/edit_event_screen.dart';
import '../features/events/data/event.dart';
import '../features/friends/presentation/friends_screen.dart';
import '../features/groups/presentation/groups_screen.dart';
import '../features/groups/presentation/group_detail_screen.dart';
import '../features/groups/presentation/crew_detail_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/home/presentation/splash_screen.dart';
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

  // Overlay (top-level, not a branch).
  static const settings = '/settings';

  static const createEvent = '/events/new';

  /// Detail route for one event. Path: /events/:id
  static String eventDetail(String id) => '/events/$id';

  /// Edit route for one event. Path: /events/:id/edit (pass the Event as extra)
  static String eventEdit(String id) => '/events/$id/edit';

  /// Detail routes within the Groups branch.
  static String groupDetail(String id) => '/groups/group/$id';
  static String crewDetail(String id) => '/groups/crew/$id';
}

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Rebuild routing decisions whenever auth or the profile changes.
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(currentSessionProvider);
      final loc = state.matchedLocation;
      final loggingIn = loc == AppRoutes.signIn || loc == AppRoutes.signUp;

      // 1. No session -> must authenticate.
      if (session == null) {
        return loggingIn ? null : AppRoutes.signIn;
      }

      // 2. Signed in: do we know the profile yet?
      final profileAsync = ref.read(myProfileProvider);
      // While the profile is loading on cold start, hold on the splash.
      if (profileAsync.isLoading && !profileAsync.hasValue) {
        return loc == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final hasHandle = profileAsync.value?.hasHandle ?? false;
      final onOnboarding = loc == AppRoutes.onboarding;

      // 3. Signed in, no handle -> onboarding.
      if (!hasHandle) {
        return onOnboarding ? null : AppRoutes.onboarding;
      }

      // 4. Fully set up -> keep them out of auth/onboarding/splash pages.
      if (loggingIn || onOnboarding || loc == AppRoutes.splash) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      // ── Auth / onboarding / splash (outside the shell) ──────────────────
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: AppRoutes.signUp, builder: (_, _) => const SignUpScreen()),
      GoRoute(
          path: AppRoutes.onboarding,
          builder: (_, _) => const OnboardingScreen()),

      // ── Settings: top-level overlay, not a branch ──────────────────────
      GoRoute(
          path: AppRoutes.settings, builder: (_, _) => const SettingsScreen()),

      // ── The signed-in app shell: nav rail + four branches ──────────────
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
                GoRoute(
                  path: ':id',
                  builder: (context, state) =>
                      EventDetailScreen(eventId: state.pathParameters['id']!),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (context, state) =>
                          EditEventScreen(event: state.extra! as Event),
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
          // Groups (+ group/crew detail as pushes within this branch)
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
                GoRoute(
                  path: 'crew/:id',
                  builder: (context, state) =>
                      CrewDetailScreen(crewId: state.pathParameters['id']!),
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
