/// AppShell — the persistent navigation frame for signed-in users: a bottom
/// NavigationBar (Home / Events / Friends / Groups). Each destination is a
/// branch of a StatefulShellRoute, so switching tabs preserves each branch's
/// own nav stack.
///
/// This is pure chrome: it holds no business or visibility logic. Settings now
/// lives under Profile (reached via the avatar in each screen's app bar), so it
/// is no longer a nav destination here.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  /// Provided by StatefulShellRoute.indexedStack — controls the active branch.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: t.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.event_outlined),
            selectedIcon: const Icon(Icons.event_rounded),
            label: t.navEvents,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people_rounded),
            label: t.navFriends,
          ),
          NavigationDestination(
            icon: const Icon(Icons.workspaces_outline),
            selectedIcon: const Icon(Icons.workspaces_rounded),
            label: t.navGroups,
          ),
        ],
      ),
    );
  }

  /// Tapping the current branch's destination pops it to root; tapping another
  /// switches branches. This is go_router's recommended pattern.
  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
