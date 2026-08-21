/// A full-height editor for the event description, sliding up from the bottom
/// with rounded top corners.
///
/// The description is the one event field that is a *paragraph* rather than a
/// value — the inline tick/cross editor used for the date and the location gave
/// it five cramped lines to live in. Date and location keep that inline editor;
/// only this field gets a page.
///
/// Header, left to right: back (discard), the field's name, undo, and the save
/// button. Undo is a real per-keystroke history via [UndoHistoryController],
/// not a "revert everything" — it steps back through what you typed, and is
/// disabled when there is nothing to step back to.
///
/// Purely presentational: it hands the new text back through [showDescription
/// Editor]'s future and never touches a repository itself.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';

/// Opens the editor for [initial] and resolves to the text the user saved, or
/// null if they backed out. An empty string is a real answer — it means the
/// description was cleared.
Future<String?> showDescriptionEditor(
  BuildContext context, {
  required String initial,
  int? maxLength,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    // Below the status bar, so the rounded top corners are actually visible
    // and the sheet reads as a sheet rather than as a new screen.
    useSafeArea: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    // Dismissing by dragging or tapping the scrim would throw away a paragraph
    // without asking; leaving is the back button's job, which confirms first.
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _DescriptionEditor(initial: initial, maxLength: maxLength),
  );
}

class _DescriptionEditor extends StatefulWidget {
  const _DescriptionEditor({required this.initial, this.maxLength});
  final String initial;
  final int? maxLength;

  @override
  State<_DescriptionEditor> createState() => _DescriptionEditorState();
}

class _DescriptionEditorState extends State<_DescriptionEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  final _undo = UndoHistoryController();

  @override
  void dispose() {
    _controller.dispose();
    _undo.dispose();
    super.dispose();
  }

  bool get _dirty => _controller.text.trim() != widget.initial.trim();

  Future<void> _back() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final t = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.descriptionDiscardTitle),
        content: Text(t.descriptionDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.descriptionDiscardConfirm),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    // The system back gesture pops the sheet directly, which would skip the
    // discard confirmation the header's back arrow does. Route it through the
    // same path instead.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Padding(
        // The sheet is full height, so the keyboard has to take its space out
        // of the editor rather than push the whole thing off-screen.
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox.expand(
          child: Column(
            children: [
              _Header(onBack: _back, onSave: _save, undo: _undo),
              Divider(height: 1, color: AppColors.outline),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: TextField(
                    controller: _controller,
                    undoController: _undo,
                    autofocus: true,
                    // Fills the sheet: the box IS the page, so there is no
                    // scrollbar-inside-a-box and no fixed line count.
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    maxLength: widget.maxLength,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: Theme.of(context).textTheme.bodyLarge,
                    decoration: InputDecoration(
                      hintText: t.descriptionHint,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Back · title · undo · save, all on one row.
class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.onSave,
    required this.undo,
  });

  final VoidCallback onBack;
  final VoidCallback onSave;
  final UndoHistoryController undo;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          Expanded(
            child: Text(
              t.detailDescription,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          // Greyed out until there is something to undo, so the arrow never
          // looks like it did nothing.
          ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: undo,
            builder: (context, value, _) => IconButton(
              onPressed: value.canUndo ? undo.undo : null,
              icon: const Icon(Icons.undo),
              tooltip: t.descriptionUndo,
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(
              // The theme's filled buttons are full-width page actions (52 tall,
              // stretched); this one sits in a header row.
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(t.descriptionSave),
          ),
        ],
      ),
    );
  }
}
