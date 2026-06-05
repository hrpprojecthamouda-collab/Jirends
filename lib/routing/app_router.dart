/// App router. The redirect guard is where the auth + onboarding flow lives:
///
///   no session            -> /sign-in
///   session, no handle    -> /onboarding
///   session, has handle   -> / (home)
///
/// Visibility of *events* is NOT decided here — that is the database's job
/// (the cardinal rule). This guard only gates auth and the one-time handle
/// onboarding step.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/supabase/supabase_providers.dart';
import '../features/auth/data/profile_repository.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/auth/presentation/sign_up_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/home/presentation/splash_screen.dart';

class AppRoutes {
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const onboarding = '/onboarding';
  static const home = '/';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Rebuild routing decisions whenever auth or the profile changes.
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(currentSessionProvider);
      final loggingIn = state.matchedLocation == AppRoutes.signIn ||
          state.matchedLocation == AppRoutes.signUp;

      // 1. No session -> must authenticate.
      if (session == null) {
        return loggingIn ? null : AppRoutes.signIn;
      }

      // 2. Signed in: do we know the profile yet?
      final profileAsync = ref.read(myProfileProvider);
      // While the profile is loading we hold on the splash to avoid flicker.
      if (profileAsync.isLoading && !profileAsync.hasValue) {
        return null; // stay; splash shows under the home route below
      }

      final hasHandle = profileAsync.value?.hasHandle ?? false;
      final onOnboarding = state.matchedLocation == AppRoutes.onboarding;

      // 3. Signed in, no handle -> onboarding.
      if (!hasHandle) {
        return onOnboarding ? null : AppRoutes.onboarding;
      }

      // 4. Fully set up -> keep them out of auth/onboarding pages.
      if (loggingIn || onOnboarding) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) {
          // Show splash while the profile is still resolving on cold start.
          final profileAsync = ProviderScope.containerOf(context).read(myProfileProvider);
          if (profileAsync.isLoading && !profileAsync.hasValue) {
            return const SplashScreen();
          }
          return const HomeScreen();
        },
      ),
      GoRoute(path: AppRoutes.signIn, builder: (context, state) => const SignInScreen()),
      GoRoute(path: AppRoutes.signUp, builder: (context, state) => const SignUpScreen()),
      GoRoute(path: AppRoutes.onboarding, builder: (context, state) => const OnboardingScreen()),
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
