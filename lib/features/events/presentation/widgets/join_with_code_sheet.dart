/// "Have an invite code?" — redeem an invite by pasting it.
///
/// WHY THIS EXISTS. A `jirends://` link is not tappable in messaging apps:
/// they linkify http/https only, and an in-app browser handed a custom scheme
/// tries to fetch it as a web page and reports "webpage not available". The
/// URL never reaches Android's intent system, so the app is never consulted.
/// A code is just text, so it survives every messenger, every email client and
/// being read aloud.
///
/// This is not a replacement for the deep link, it is the floor under it. Once
/// a domain serves App Links the shared message gains a tappable https URL and
/// this becomes the fallback for anyone whose client still mangles it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../auth/application/auth_controller.dart';
import '../../data/invite_repository.dart';

Future<void> showJoinWithCodeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => const _JoinWithCodeSheet(),
  );
}

class _JoinWithCodeSheet extends ConsumerStatefulWidget {
  const _JoinWithCodeSheet();

  @override
  ConsumerState<_JoinWithCodeSheet> createState() => _JoinWithCodeSheetState();
}

class _JoinWithCodeSheetState extends ConsumerState<_JoinWithCodeSheet> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillFromClipboard();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// If the clipboard already holds something code-shaped, offer it. Nobody
  /// arrives here without having just copied a code, so making them paste it
  /// by hand is a step for nothing.
  Future<void> _prefillFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final token = extractToken(data?.text ?? '');
    if (token == null || !mounted) return;
    _input.text = token;
  }

  Future<void> _join() async {
    final token = extractToken(_input.text);
    if (token == null) {
      setState(() => _error = AppLocalizations.of(context).joinCodeInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final eventId = await ref.read(inviteRepositoryProvider).join(token);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.push(AppRoutes.eventDetail(eventId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = messageForError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.joinCodeTitle,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(t.joinCodeHint,
              style: TextStyle(color: AppColors.inkMuted)),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            autofocus: true,
            enabled: !_busy,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _busy ? null : _join(),
            decoration: InputDecoration(
              hintText: t.joinCodeField,
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _join,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.joinCodeAction),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pull an invite token out of whatever the user pasted.
///
/// Deliberately forgiving, because people paste the whole message: a bare
/// code, a jirends:// link, an https link, or a line of text with the code at
/// the end. Returns null when there is nothing token-shaped.
///
/// Tokens are 22 url-safe base64 characters (16 random bytes), which is what
/// makes them recognisable in a blob of text.
String? extractToken(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  // A URL in any scheme: take the segment after /join/.
  final uri = Uri.tryParse(text);
  if (uri != null && uri.pathSegments.length == 2 &&
      uri.pathSegments.first == 'join') {
    final t = uri.pathSegments[1];
    return _looksLikeToken(t) ? t : null;
  }

  // Otherwise scan for the first token-shaped run. This catches both a bare
  // code and a pasted message that happens to contain one.
  final match =
      RegExp(r'[A-Za-z0-9_-]{20,26}').allMatches(text).map((m) => m.group(0)!);
  for (final candidate in match) {
    if (_looksLikeToken(candidate)) return candidate;
  }
  return null;
}

bool _looksLikeToken(String s) =>
    s.length >= 20 && s.length <= 26 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s);
