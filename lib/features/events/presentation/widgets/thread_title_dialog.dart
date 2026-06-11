/// ThreadTitleDialog — name/rename a comment discussion. Returns the trimmed
/// title via `Navigator.pop` (empty string = clear), or null when cancelled.
/// Owns its TextEditingController (disposed in its own dispose) — avoids the
/// dispose-after-await dialog crash.
library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

class ThreadTitleDialog extends StatefulWidget {
  const ThreadTitleDialog({super.key, required this.initial});
  final String initial;

  @override
  State<ThreadTitleDialog> createState() => _ThreadTitleDialogState();
}

class _ThreadTitleDialogState extends State<ThreadTitleDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.discussionRename),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: 120,
        decoration:
            InputDecoration(labelText: t.discussionTitleLabel, counterText: ''),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_c.text.trim()),
          child: Text(t.commonAdd),
        ),
      ],
    );
  }
}
