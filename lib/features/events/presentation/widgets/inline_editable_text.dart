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
          Icon(widget.leading, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: 10),
        ],
        Expanded(child: Text(text, style: style)),
        if (widget.canEdit)
          const Icon(Icons.edit_outlined, size: 16, color: AppColors.inkMuted),
      ],
    );

    if (!widget.canEdit) return content;
    return InkWell(
      onTap: _start,
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
                    icon: const Icon(Icons.check, color: AppColors.teal),
                    onPressed: _confirm,
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
                    icon: const Icon(Icons.close, color: AppColors.coral),
                    onPressed: _cancel,
                  ),
                ],
              ),
      ],
    );
  }
}
