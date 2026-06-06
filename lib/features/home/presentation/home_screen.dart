/// Home — an activity feed of recent goings-on across the user's VISIBLE events
/// (RSVPs, comments, claimed items). STUB for Slice 1: themed shell + empty
/// state. The real feed is a later slice.
///
/// CARDINAL-RULE NOTE: when the real feed is built, every item must be derived
/// only from rows the viewer's RLS already returns, and must never name or hint
/// at an event the viewer can't see. The feed reads from the same membership-
/// scoped tables, so this is safe by construction — but it is a side channel, so
/// keep it in mind.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../auth/data/profile_repository.dart';
import '../../shell/presentation/placeholder_body.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final handle = ref.watch(myProfileProvider).value?.handle;

    return Scaffold(
      appBar: AppBar(
        title: Text(handle == null ? t.homeTitle : '${t.homeTitle} · $handle'),
      ),
      body: PlaceholderBody(
        icon: Icons.bolt_outlined,
        message: t.homeActivityEmpty,
      ),
    );
  }
}
