/// Shared dialogs for the Groups feature — a simple "enter a name" dialog used
/// to create a selection group, plus a confirm-delete helper.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';

/// Prompt for a name and run [onSubmit] with the trimmed value (if non-empty).
/// The text controller is owned by [_NameDialog] (a StatefulWidget) so it is
/// disposed only after the route is fully removed — disposing it right after the
/// await would fire the framework's `_dependents.isEmpty` assertion while the
/// dismissing TextField still depends on it.
Future<void> showCreateNameDialog(
  BuildContext context, {
  required String title,
  required String label,
  required Future<void> Function(String name) onSubmit,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, label: label),
  );
  if (name != null && name.trim().isNotEmpty) {
    await onSubmit(name.trim());
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.label});
  final String title;
  final String label;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(t.commonAdd),
        ),
      ],
    );
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
