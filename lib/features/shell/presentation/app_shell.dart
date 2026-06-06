/// AppShell — the persistent navigation frame for signed-in users. A narrow,
/// icon-only left rail (Home / Events / Friends / Groups) with a Settings gear
/// pinned at the bottom. Each rail destination is a branch of a
/// StatefulShellRoute, so switching tabs preserves each branch's own nav stack.
///
/// This is pure chrome: it holds no business or visibility logic. The gear is a
/// top-level route (an overlay), not a branch, so opening Settings doesn't
/// disturb the four branches' state.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/app_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  /// Provided by StatefulShellRoute.indexedStack — controls the active branch.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    final destinations = <_Dest>[
      _Dest(Icons.home_outlined, Icons.home_rounded, t.navHome),
      _Dest(Icons.event_outlined, Icons.event_rounded, t.navEvents),
      _Dest(Icons.people_outline, Icons.people_rounded, t.navFriends),
      _Dest(Icons.workspaces_outline, Icons.workspaces_rounded, t.navGroups),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            minWidth: 72,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onTap,
            // Brand mark up top, settings gear pinned at the bottom.
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Icon(Icons.celebration_rounded,
                  color: AppColors.violet, size: 28),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Tooltip(
                    message: t.navSettings,
                    child: IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      color: AppColors.inkMuted,
                      onPressed: () => context.go(AppRoutes.settings),
                    ),
                  ),
                ),
              ),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Tooltip(message: d.label, child: Icon(d.icon)),
                  selectedIcon:
                      Tooltip(message: d.label, child: Icon(d.selectedIcon)),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: navigationShell),
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

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
