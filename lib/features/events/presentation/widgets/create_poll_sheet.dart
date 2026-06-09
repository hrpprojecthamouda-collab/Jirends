/// Create-poll bottom sheet: question, kind (date/place only for organizers),
/// mode (majority / weighted wheel), and 2..N option labels. Owns its text
/// controllers in State so they're disposed safely. Returns nothing; it calls
/// the action controller and pops on success.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/poll_controller.dart';
import '../../data/poll.dart';

Future<void> showCreatePollSheet(
  BuildContext context, {
  required String eventId,
  required bool isOrganizer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _CreatePollSheet(eventId: eventId, isOrganizer: isOrganizer),
  );
}

class _CreatePollSheet extends ConsumerStatefulWidget {
  const _CreatePollSheet({required this.eventId, required this.isOrganizer});
  final String eventId;
  final bool isOrganizer;

  @override
  ConsumerState<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends ConsumerState<_CreatePollSheet> {
  final _question = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  PollKind _kind = PollKind.general;
  PollMode _mode = PollMode.majority;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final q = _question.text.trim();
    final labels = _options.map((c) => c.text.trim()).where((l) => l.isNotEmpty).toList();
    if (q.isEmpty) {
      setState(() => _error = t.pollNeedQuestion);
      return;
    }
    if (labels.length < 2) {
      setState(() => _error = t.pollNeedTwoOptions);
      return;
    }
    final ok = await ref.read(pollActionsControllerProvider.notifier).create(
          widget.eventId,
          question: q,
          kind: _kind,
          mode: _mode,
          labels: labels,
        );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final loading = ref.watch(pollActionsControllerProvider).isLoading;
    // date/place kinds are organizer-only.
    final kinds = widget.isOrganizer
        ? PollKind.values
        : [PollKind.general];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.pollNew, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _question,
              maxLength: 200,
              decoration: InputDecoration(
                  labelText: t.pollQuestion, hintText: t.pollQuestionHint),
            ),
            const SizedBox(height: 8),

            Text(t.pollKind, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final k in kinds)
                  ChoiceChip(
                    label: Text(_kindLabel(t, k)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            Text(t.pollMode, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(t.pollModeMajority),
                  selected: _mode == PollMode.majority,
                  onSelected: (_) => setState(() => _mode = PollMode.majority),
                ),
                ChoiceChip(
                  label: Text(t.pollModeWheel),
                  selected: _mode == PollMode.weightedRandom,
                  onSelected: (_) =>
                      setState(() => _mode = PollMode.weightedRandom),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Option fields.
            for (var i = 0; i < _options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _options[i],
                        maxLength: 120,
                        decoration: InputDecoration(
                          labelText: '${t.pollOption} ${i + 1}',
                          counterText: '',
                        ),
                      ),
                    ),
                    if (_options.length > 2)
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.inkMuted),
                        onPressed: () =>
                            setState(() => _options.removeAt(i).dispose()),
                      ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _options.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: Text(t.pollAddOption),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: const TextStyle(color: AppColors.coral)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: loading ? null : _submit,
              child: loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.pollCreate),
            ),
          ],
        ),
      ),
    );
  }

  String _kindLabel(AppLocalizations t, PollKind k) => switch (k) {
        PollKind.general => t.pollKindGeneral,
        PollKind.date => t.pollKindDate,
        PollKind.place => t.pollKindPlace,
      };
}
