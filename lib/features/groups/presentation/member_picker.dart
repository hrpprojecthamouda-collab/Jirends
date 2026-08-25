/// A bottom-sheet picker that lets the user choose one [Profile] from a list of
/// candidates (e.g. their friends not already in a group). Returns the chosen
/// profile, or null if dismissed. Shows [emptyMessage] when there are none.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/profile.dart';
import '../../profile/presentation/user_avatar.dart';

/// Wait for the data a picker is about to show, reporting a failure instead of
/// throwing. Returns null when it could not be loaded, meaning "do not open".
///
/// Every picker in the app used to build its candidate list from
/// `ref.read(someListProvider).value ?? const []`. That reads whatever the
/// provider is holding AT THAT INSTANT, and a top-level provider nothing has
/// subscribed to yet is holding AsyncLoading with no value — so the first time
/// you opened "Add a friend" without having visited the Friends screen, the
/// picker was built from an empty list. Visiting Friends warmed the provider,
/// which is why the second attempt looked fine and the bug seemed random.
///
/// Awaiting `provider.future` instead asks for the first REAL value, whether
/// that is already in hand (returns immediately) or still in flight.
Future<T?> loadForPicker<T>(BuildContext context, Future<T> data) async {
  try {
    return await data;
  } catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(messageForError(e))));
    return null;
  }
}

/// A generic id→label picker (e.g. choose a group). Returns the chosen
/// id, or null if dismissed. Shows [emptyMessage] when there are none.
Future<String?> showGenericPicker(
  BuildContext context, {
  required Map<String, String> labels,
  required String emptyMessage,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (context) {
      if (labels.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted)),
        );
      }
      final entries = labels.entries.toList();
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          for (final e in entries)
            ListTile(
              title: Text(e.value),
              onTap: () => Navigator.of(context).pop(e.key),
            ),
        ],
      );
    },
  );
}

Future<Profile?> showMemberPicker(
  BuildContext context, {
  required List<Profile> candidates,
  required String emptyMessage,
}) {
  return showModalBottomSheet<Profile>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (context) {
      if (candidates.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted)),
        );
      }
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          for (final p in candidates)
            ListTile(
              leading: UserAvatar(profile: p),
              title: Text(p.handle ?? '…'),
              onTap: () => Navigator.of(context).pop(p),
            ),
        ],
      );
    },
  );
}
