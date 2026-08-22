/// CommentComposeBubble — the rounded pill used to post a new top-level
/// comment, rendered directly beneath the comment thread in the Overview page.
/// Idle (not focused, empty) it sits at 50% opacity so it reads as "present
/// but out of the way"; tapping it (or having text in it) brings it to full
/// opacity.
///
/// It scrolls with the page rather than floating over it: an earlier floating
/// version covered whichever section happened to sit beneath it (Polls, Files)
/// and swallowed their taps. Layout/placement is the caller's job — this
/// widget only owns the bubble itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/comment_controller.dart';
import '../../application/event_detail_controller.dart';
import 'mention_suggestions.dart';

class CommentComposeBubble extends ConsumerStatefulWidget {
  const CommentComposeBubble({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<CommentComposeBubble> createState() =>
      _CommentComposeBubbleState();
}

class _CommentComposeBubbleState extends ConsumerState<CommentComposeBubble> {
  final _input = TextEditingController();
  final _focusNode = FocusNode();
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _input.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _input.removeListener(_onTextChange);
    _focusNode.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onFocusChange() => setState(() => _active = _computeActive());
  void _onTextChange() => setState(() => _active = _computeActive());

  /// The mention being typed right now, or null. Recomputed on every build
  /// from the controller rather than cached, so it stays correct when the
  /// caret moves without the text changing.
  MentionQuery? get _mention => _focusNode.hasFocus
      ? mentionQueryAt(_input.text, _input.selection.baseOffset)
      : null;

  void _insertMention(MentionQuery query, profile) {
    final result = applyMention(_input.text, query, profile);
    _input.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.caret),
    );
    // Stay in the field: people usually keep typing after a mention.
    _focusNode.requestFocus();
  }
  bool _computeActive() => _focusNode.hasFocus || _input.text.isNotEmpty;

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    final ok = await ref
        .read(commentActionsControllerProvider.notifier)
        .add(widget.eventId, body);
    // Backing out of the event while the post is in flight disposes both
    // controllers; touching them afterwards throws "used after being disposed".
    if (!mounted) return;
    if (ok) {
      _input.clear();
      _focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    // Members only — a mention notification names its event, so it may only
    // ever reach someone who can already see it (comment_mentions.sql).
    final myId = ref.watch(currentUserIdProvider);
    final members =
        ref.watch(eventMembersProvider(widget.eventId)).value ?? const [];
    final query = _mention;
    final matches = query == null
        ? const []
        : matchMembers(
            [for (final m in members) if (m.userId != myId) m],
            query.text,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (query != null)
          MentionSuggestions(
            matches: matches.cast(),
            onPick: (profile) => _insertMention(query, profile),
          ),
        _bubble(context, t),
      ],
    );
  }

  Widget _bubble(BuildContext context, AppLocalizations t) {
    return AnimatedOpacity(
      opacity: _active ? 1.0 : 0.5,
      duration: const Duration(milliseconds: 180),
      child: Material(
        color: AppColors.surface,
        elevation: 4,
        shadowColor: Colors.black45,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: t.commentHint,
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                icon: const Icon(Icons.send),
                onPressed: _send,
                tooltip: t.commentSend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
