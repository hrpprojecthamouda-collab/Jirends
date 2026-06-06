/// Groups — STUB for Slice 1. The real screen (friend groups as a selection
/// shortcut that never retroactively exposes past events — see rls_tests TEST 6)
/// is a later slice.
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../shell/presentation/placeholder_body.dart';

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.groupsTitle)),
      body: PlaceholderBody(
        icon: Icons.workspaces_outline,
        message: t.groupsComingSoon,
      ),
    );
  }
}
