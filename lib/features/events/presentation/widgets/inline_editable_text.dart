/// InlineEditableText — tap-to-edit text. In display mode it shows [value] (or
/// a muted [placeholder]); when [canEdit], tapping switches to an inline text
/// box with a tick (confirm) and cross (cancel). Confirming calls [onSubmit]
/// with the new text (empty string means "cleared").
///
/// Dumb and self-contained: it owns only its own editing UI state; persistence
/// is the caller's job via [onSubmit].
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class InlineEditableText extends StatefulWidget {
  const InlineEditableText({
    super.key,
    required this.value,
    required this.placeholder,
    required this.canEdit,
    required this.onSubmit,
    this.style,
    this.multiline = false,
    this.maxLength,
    this.leading,
    this.onEditTap,
  });

  final String value;
  final String placeholder;
  final bool canEdit;
  final Future<void> Function(String) onSubmit;
  final TextStyle? style;
  final bool multiline;
  final int? maxLength;

  /// Optional leading icon shown before the text in display mode.
  final IconData? leading;

  /// When set, tapping hands editing over to this instead of switching to the
  /// inline box — for a field that has outgrown a few lines and wants a page of
  /// its own (the description). Display mode is unchanged either way, so the
  /// field still looks like every other tappable field on the event.
  final VoidCallback? onEditTap;

  @override
  State<InlineEditableText> createState() => _InlineEditableTextState();
}

class _InlineEditableTextState extends State<InlineEditableText> {
  bool _editing = false;
  bool _saving = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    _controller.text = widget.value;
    setState(() => _editing = true);
  }

  void _cancel() => setState(() => _editing = false);

  Future<void> _confirm() async {
    setState(() => _saving = true);
    await widget.onSubmit(_controller.text.trim());
    if (mounted) {
      setState(() {
        _saving = false;
        _editing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) return _editor(context);
    return _display(context);
  }

  Widget _display(BuildContext context) {
    final hasValue = widget.value.trim().isNotEmpty;
    final text = hasValue ? widget.value : widget.placeholder;
    final style = (widget.style ?? Theme.of(context).textTheme.bodyLarge)
        ?.copyWith(color: hasValue ? AppColors.ink : AppColors.inkMuted);

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.leading != null) ...[
          // Full ink for the same reason as the calendar: these fields
          // carry no text label, so the icon does the naming.
          Icon(widget.leading, size: 18, color: AppColors.ink),
          const SizedBox(width: 10),
        ],
        // No trailing edit pen. It reserved ~16px of every line for an icon
        // that repeated on every field, and the description paid for it in
        // early wraps. The row stays tappable for anyone who canEdit.
        Expanded(child: Text(text, style: style)),
      ],
    );

    if (!widget.canEdit) return content;
    return InkWell(
      onTap: widget.onEditTap ?? _start,
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: content),
    );
  }

  Widget _editor(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            autofocus: true,
            // Edit at the size it displays at. Without this a location typed
            // at the TextField's default bodyLarge visibly shrank on save.
            style: widget.style,
            minLines: widget.multiline ? 2 : 1,
            maxLines: widget.multiline ? 5 : 1,
            maxLength: widget.maxLength,
            enabled: !_saving,
            textInputAction:
                widget.multiline ? TextInputAction.newline : TextInputAction.done,
            onSubmitted: widget.multiline ? null : (_) => _confirm(),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.placeholder,
              counterText: '',
            ),
          ),
        ),
        const SizedBox(width: 4),
        _saving
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).okButtonLabel,
                    icon: Icon(Icons.check, color: AppColors.teal),
                    onPressed: _confirm,
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
                    icon: Icon(Icons.close, color: AppColors.coral),
                    onPressed: _cancel,
                  ),
                ],
              ),
      ],
    );
  }
}
