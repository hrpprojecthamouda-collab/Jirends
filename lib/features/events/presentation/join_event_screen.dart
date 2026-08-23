/// JoinEventScreen — what an invite link opens.
///
/// Three states, and the order matters:
///
///  1. **Signed out.** Stash the token and offer to sign in. The router lets
///     /join through while signed out precisely so this can happen; bouncing to
///     /sign-in directly would swallow the token and the link would look dead.
///  2. **Signed in, peeking.** Show the event's title and head-count so the
///     user knows what they are accepting. That is all `peek_invite` returns —
///     no description, no roster, not even the event id.
///  3. **Joined.** Replace this screen with the event itself.
///
/// An unknown, expired or revoked token is one message, deliberately: the RPC
/// cannot tell them apart either, so the link is never an oracle for which
/// tokens are real.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/weekday.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/app_router.dart';
import '../../auth/application/auth_controller.dart';
import '../data/invite_repository.dart';

class JoinEventScreen extends ConsumerStatefulWidget {
  const JoinEventScreen({super.key, required this.token});
  final String token;

  @override
  ConsumerState<JoinEventScreen> createState() => _JoinEventScreenState();
}

class _JoinEventScreenState extends ConsumerState<JoinEventScreen> {
  Future<InvitePreview?>? _preview;
  bool _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The token has arrived and we are on the join screen, so whatever the
    // router stashed is now in hand. Clearing it here stops the redirect from
    // firing again and looping.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(pendingInviteProvider) != null) {
        ref.read(pendingInviteProvider.notifier).set(null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final signedIn = ref.watch(currentUserIdProvider) != null;

    // peek_invite is granted to `authenticated` only, so there is nothing to
    // fetch until the user is signed in.
    if (signedIn) {
      _preview ??= ref.read(inviteRepositoryProvider).peek(widget.token);
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.joinTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: signedIn ? _signedIn(t) : _signedOut(t),
          ),
        ),
      ),
    );
  }

  // ── 1. Signed out ─────────────────────────────────────────────────────────
  Widget _signedOut(AppLocalizations t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mail_outline, size: 48, color: AppColors.primary),
        const SizedBox(height: 16),
        Text(t.joinSignInPrompt,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            // Stash BEFORE navigating: the router resumes it once a session
            // and a handle both exist.
            ref.read(pendingInviteProvider.notifier).set(widget.token);
            context.go(AppRoutes.signIn);
          },
          child: Text(t.joinSignInAction),
        ),
      ],
    );
  }

  // ── 2. Signed in ──────────────────────────────────────────────────────────
  Widget _signedIn(AppLocalizations t) {
    return FutureBuilder<InvitePreview?>(
      future: _preview,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _message(t.joinFailed, snap.error);
        final p = snap.data;
        // Unknown, expired, revoked — one message for all three, on purpose.
        if (p == null) return _message(t.joinInvalid, null);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(t.joinInvitedTo,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.inkMuted, letterSpacing: 1.1)),
            const SizedBox(height: 8),
            Text(p.eventTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            if (p.startsAt != null)
              _line(Icons.event_outlined,
                  '${weekdayShort(t, p.startsAt!.toLocal())} '
                  '${_fmt(p.startsAt!.toLocal())}'),
            if (p.organizerLabel.isNotEmpty)
              _line(Icons.person_outline, p.organizerLabel),
            _line(Icons.group_outlined, t.membersCount(p.memberCount)),
            const SizedBox(height: 28),
            if (_error != null) ...[
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.coral)),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _joining ? null : () => _join(p),
                child: _joining
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(p.alreadyMember ? t.joinOpen : t.joinAction),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.inkMuted),
            const SizedBox(width: 8),
            Flexible(child: Text(text)),
          ],
        ),
      );

  Widget _message(String text, Object? error) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_off, size: 48, color: AppColors.inkMuted),
          const SizedBox(height: 16),
          Text(text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(messageForError(error),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMuted)),
          ],
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => context.go(AppRoutes.home),
            child: Text(AppLocalizations.of(context).joinBackHome),
          ),
        ],
      );

  Future<void> _join(InvitePreview p) async {
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final eventId =
          await ref.read(inviteRepositoryProvider).join(widget.token);
      if (!mounted) return;
      // Replace, not push: backing out of the event should not land on a stale
      // invite screen.
      context.go(AppRoutes.eventDetail(eventId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = messageForError(e);
      });
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
