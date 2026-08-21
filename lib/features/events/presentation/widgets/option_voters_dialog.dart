/// The press-and-hold voters panel: who backed one poll option.
///
/// Opens from the option you held rather than from nowhere — the box scales up
/// out of that row's position and settles in the middle of a dimmed screen, so
/// the connection between what you pressed and what appeared is never in
/// doubt. Dismissed by tapping the dimmed area or with the system back
/// gesture/button (barrierDismissible handles both).
///
/// Votes are visible to every member of the event at any time, open poll or
/// closed — the old ballot secrecy (VIS-7) was deliberately retired. Still
/// member-scoped: the rows this reads come from an RLS-gated query, so a
/// non-member (and therefore a surprise target) can never reach them.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/poll_vote.dart';
import '../../../profile/presentation/user_avatar.dart';

/// Show the voters for one option, growing out of [origin] (a point in global
/// screen coordinates, normally the centre of the option row).
Future<void> showOptionVotersDialog(
  BuildContext context, {
  required Offset origin,
  required String optionLabel,
  required List<PollVote> voters,
}) {
  final size = MediaQuery.of(context).size;
  // Translate the tapped point into an Alignment so the scale transition
  // appears to originate there. Alignment runs -1..1 across the screen.
  final alignment = Alignment(
    (origin.dx / size.width) * 2 - 1,
    (origin.dy / size.height) * 2 - 1,
  );

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    // Named so tapping the dimmed area dismisses; also what the back gesture
    // pops.
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: .55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, _, _) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: curved,
          alignment: alignment,
          child: _VotersPanel(optionLabel: optionLabel, voters: voters),
        ),
      );
    },
  );
}

class _VotersPanel extends StatelessWidget {
  const _VotersPanel({required this.optionLabel, required this.voters});
  final String optionLabel;
  final List<PollVote> voters;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;

    return Center(
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: size.width * 0.82,
            maxHeight: size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      optionLabel,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.pollVoters(voters.length),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.outline),
              Flexible(
                child: voters.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                        child: Text(
                          t.pollNoVotersYet,
                          style: TextStyle(color: AppColors.inkMuted),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (final v in voters)
                            ListTile(
                              dense: true,
                              leading: UserAvatar(
                                profile: v.voter,
                                radius: 16,
                                background: AppColors.surfaceHi,
                                foreground: AppColors.ink,
                              ),
                              title: Text(v.voter?.handle ?? '…'),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
