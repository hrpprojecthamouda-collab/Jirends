/// History tab — a read-only change log for the event: edits to title,
/// description, status, location, start/end time, and poll lifecycle
/// (created / closed + result / reopened). RLS-scoped to members; the DB logs
/// every entry, so this just renders what the provider returns.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/event_history_controller.dart';
import '../../data/event_history_entry.dart';

class HistoryTab extends ConsumerWidget {
  const HistoryTab({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final historyAsync = ref.watch(eventHistoryProvider(eventId));

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(messageForError(e))),
      data: (entries) => entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t.historyEmpty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.inkMuted)),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: entries.length,
              itemBuilder: (context, i) => _HistoryTile(entry: entries[i]),
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});
  final EventHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final who = entry.actor?.handle ?? t.historySomeone;
    final kind = entry.kindEnum;

    final (icon, color) = _iconFor(kind);
    final headline = _headline(t, who);
    final detailLine = _detailLine(t);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Icon(icon, size: 18, color: color),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (detailLine != null) ...[
                    const SizedBox(height: 2),
                    Text(detailLine,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.inkMuted)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_time(entry.createdAt.toLocal()),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.inkMuted)),
          ],
        ),
      ),
    );
  }

  (IconData, Color) _iconFor(HistoryKind k) => switch (k) {
        HistoryKind.title => (Icons.title, AppColors.violet),
        HistoryKind.description => (Icons.notes, AppColors.violet),
        HistoryKind.status => (Icons.flag_outlined, AppColors.teal),
        HistoryKind.location => (Icons.place_outlined, AppColors.blue),
        HistoryKind.startsAt => (Icons.schedule, AppColors.blue),
        HistoryKind.endsAt => (Icons.schedule, AppColors.blue),
        HistoryKind.pollCreated => (Icons.how_to_vote, AppColors.violet),
        HistoryKind.pollClosed => (Icons.how_to_vote, AppColors.teal),
        HistoryKind.pollReopened => (Icons.refresh, AppColors.blue),
        HistoryKind.other => (Icons.history, AppColors.inkMuted),
      };

  String _fieldLabel(AppLocalizations t, HistoryKind k) => switch (k) {
        HistoryKind.title => t.historyFieldTitle,
        HistoryKind.description => t.historyFieldDescription,
        HistoryKind.status => t.historyFieldStatus,
        HistoryKind.location => t.historyFieldLocation,
        HistoryKind.startsAt => t.historyFieldStarts,
        HistoryKind.endsAt => t.historyFieldEnds,
        _ => '',
      };

  /// The first line: "{who} changed/set/cleared the {field}" or a poll line.
  String _headline(AppLocalizations t, String who) {
    final k = entry.kindEnum;
    switch (k) {
      case HistoryKind.pollCreated:
        return t.historyPollCreated(who, entry.pollQuestion ?? '');
      case HistoryKind.pollClosed:
        return t.historyPollClosed(who, entry.pollQuestion ?? '');
      case HistoryKind.pollReopened:
        return t.historyPollReopened(who, entry.pollQuestion ?? '');
      case HistoryKind.other:
        return who;
      default:
        final field = _fieldLabel(t, k);
        final hadOld = (entry.oldValue?.isNotEmpty ?? false);
        final hasNew = (entry.newValue?.isNotEmpty ?? false);
        if (!hadOld && hasNew) return t.historySet(who, field);
        if (hadOld && !hasNew) return t.historyCleared(who, field);
        return t.historyChanged(who, field);
    }
  }

  /// The second line: old → new for field edits, or the poll outcome.
  String? _detailLine(AppLocalizations t) {
    final k = entry.kindEnum;
    if (k == HistoryKind.pollClosed) {
      return switch (entry.pollOutcome) {
        'winner' => t.historyOutcomeWinner(entry.pollWinnerLabel ?? ''),
        'tie' => t.historyOutcomeTie,
        'no_votes' => t.historyOutcomeNoVotes,
        _ => null,
      };
    }
    if (k.isPoll || k == HistoryKind.other) return null;

    final old = _displayValue(k, entry.oldValue) ?? t.historyEmptyValue;
    final neu = _displayValue(k, entry.newValue) ?? t.historyEmptyValue;
    return '$old → $neu';
  }

  /// Format a stored value for display. Timestamps (starts_at/ends_at) come in
  /// as ISO strings; everything else is shown as-is.
  String? _displayValue(HistoryKind k, String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (k == HistoryKind.startsAt || k == HistoryKind.endsAt) {
      final dt = DateTime.tryParse(raw);
      if (dt != null) return _time(dt.toLocal());
    }
    return raw;
  }

  String _time(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
