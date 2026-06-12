/// Create-poll bottom sheet. Kinds: general (free question + text options),
/// day / time / place (organizer-only, auto-titled "Day/Time/Place vote" — no
/// question asked). Day options come from a date picker, time options from a
/// time picker; their typed values are applied to the event when the poll
/// closes. Owns its text controllers in State so they're disposed safely.
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

/// A picked day/time option: what the voter sees + the typed payload the
/// server applies on close.
class _PickedOption {
  const _PickedOption({required this.label, required this.value});
  final String label;
  final String value;
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
  final List<TextEditingController> _textOptions = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<_PickedOption> _picked = [];
  PollKind _kind = PollKind.general;
  PollMode _mode = PollMode.majority;
  String? _error;

  bool get _usesPicker => _kind == PollKind.date || _kind == PollKind.time;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _textOptions) {
      c.dispose();
    }
    super.dispose();
  }

  String _autoTitle(AppLocalizations t, PollKind k) => switch (k) {
        PollKind.date => t.pollTitleDay,
        PollKind.time => t.pollTitleTime,
        PollKind.place => t.pollTitlePlace,
        PollKind.general => '',
      };

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked == null || !mounted) return;
    final value =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    if (_picked.any((o) => o.value == value)) return; // no duplicates
    final label = MaterialLocalizations.of(context).formatMediumDate(picked);
    setState(() {
      _picked.add(_PickedOption(label: label, value: value));
      _error = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
    );
    if (picked == null || !mounted) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (_picked.any((o) => o.value == value)) return; // no duplicates
    final label = picked.format(context);
    setState(() {
      _picked.add(_PickedOption(label: label, value: value));
      _error = null;
    });
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);

    final String question;
    final List<String> labels;
    final List<String?>? values;
    if (_usesPicker) {
      question = _autoTitle(t, _kind);
      labels = [for (final o in _picked) o.label];
      values = [for (final o in _picked) o.value];
    } else {
      question = _kind == PollKind.place
          ? _autoTitle(t, _kind)
          : _question.text.trim();
      labels = _textOptions
          .map((c) => c.text.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      values = null;
    }

    if (question.isEmpty) {
      setState(() => _error = t.pollNeedQuestion);
      return;
    }
    if (labels.length < 2) {
      setState(() => _error = t.pollNeedTwoOptions);
      return;
    }
    final ok = await ref.read(pollActionsControllerProvider.notifier).create(
          widget.eventId,
          question: question,
          kind: _kind,
          mode: _mode,
          labels: labels,
          values: values,
        );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final loading = ref.watch(pollActionsControllerProvider).isLoading;
    // day/time/place kinds are organizer-only (their winner is applied to the
    // event, so creation must stay organizer-gated — DB trigger enforces too).
    final kinds = widget.isOrganizer
        ? const [PollKind.general, PollKind.date, PollKind.time, PollKind.place]
        : const [PollKind.general];

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
            Text(
              _kind == PollKind.general ? t.pollNew : _autoTitle(t, _kind),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            Text(t.pollKind, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final k in kinds)
                  ChoiceChip(
                    label: Text(_kindLabel(t, k)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() {
                      if (_kind == k) return;
                      _kind = k;
                      _picked.clear();
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Only a general poll asks for a question; the special kinds are
            // auto-titled and their winner is applied to the event on close.
            if (_kind == PollKind.general) ...[
              TextField(
                controller: _question,
                maxLength: 200,
                decoration: InputDecoration(
                    labelText: t.pollQuestion, hintText: t.pollQuestionHint),
              ),
              const SizedBox(height: 8),
            ] else ...[
              Text(t.pollAppliedToEvent,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.inkMuted)),
              const SizedBox(height: 12),
            ],

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

            // Options — picker-built for day/time, free text otherwise.
            if (_usesPicker) ...[
              for (var i = 0; i < _picked.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        _kind == PollKind.date
                            ? Icons.event
                            : Icons.schedule,
                        size: 18,
                        color: AppColors.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_picked[i].label)),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: AppColors.inkMuted),
                        onPressed: () =>
                            setState(() => _picked.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: _kind == PollKind.date ? _pickDay : _pickTime,
                icon: const Icon(Icons.add),
                label: Text(
                    _kind == PollKind.date ? t.pollAddDay : t.pollAddTime),
              ),
            ] else ...[
              for (var i = 0; i < _textOptions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textOptions[i],
                          maxLength: 120,
                          decoration: InputDecoration(
                            labelText: '${t.pollOption} ${i + 1}',
                            counterText: '',
                          ),
                        ),
                      ),
                      if (_textOptions.length > 2)
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.inkMuted),
                          onPressed: () => setState(
                              () => _textOptions.removeAt(i).dispose()),
                        ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _textOptions.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: Text(t.pollAddOption),
              ),
            ],

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.coral)),
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
        PollKind.time => t.pollKindTime,
        PollKind.place => t.pollKindPlace,
      };
}
