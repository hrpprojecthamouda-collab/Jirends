/// Friends — STUB for Slice 1. The real screen (handle search, directional
/// friend requests per social_layer.sql) is a later slice.
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../shell/presentation/placeholder_body.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.friendsTitle)),
      body: PlaceholderBody(
        icon: Icons.people_outline,
        message: t.friendsComingSoon,
      ),
    );
  }
}
