/// A bottom-sheet picker that lets the user choose one [Profile] from a list of
/// candidates (e.g. their friends not already in a group). Returns the chosen
/// profile, or null if dismissed. Shows [emptyMessage] when there are none.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/data/profile.dart';

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
              style: const TextStyle(color: AppColors.inkMuted)),
        );
      }
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          for (final p in candidates)
            ListTile(
              leading: CircleAvatar(
                // ignore: deprecated_member_use
                backgroundColor: AppColors.violet.withOpacity(0.18),
                foregroundColor: AppColors.violet,
                child: Text((p.nickname ?? '?').characters.first.toUpperCase()),
              ),
              title: Text(p.handle ?? '…'),
              onTap: () => Navigator.of(context).pop(p),
            ),
        ],
      );
    },
  );
}
