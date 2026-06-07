/// Shared dialogs for the Groups feature — a simple "enter a name" dialog used
/// to create both selection groups and crews, plus a confirm-delete helper.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';

/// Prompt for a name and run [onSubmit] with the trimmed value (if non-empty).
Future<void> showCreateNameDialog(
  BuildContext context, {
  required String title,
  required String label,
  required Future<void> Function(String name) onSubmit,
}) async {
  final t = AppLocalizations.of(context);
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(t.commonAdd),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name != null && name.trim().isNotEmpty) {
    await onSubmit(name.trim());
  }
}

/// Confirm a destructive action. Returns true if the user confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String message,
  required String confirmLabel,
}) async {
  final t = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.commonCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
