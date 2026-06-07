/// Create an event — title, type, description, optional date range and location,
/// and an optional SURPRISE target (a friend the event is hidden from). Status
/// is set by the DB (the type's first phase). The surprise target is enforced
/// entirely by the database (the target is never added as a member and can never
/// read the event); the picker here just sets surprise_target on insert. On
/// success we pop back to the list, which updates live via the realtime stream.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/profile.dart';
import '../../friends/application/friend_list_controller.dart';
import '../../groups/presentation/member_picker.dart';
import '../application/event_list_controller.dart';
import '../data/event.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();

  EventType _type = EventType.trip;
  DateTime? _startsAt;
  DateTime? _endsAt;
  Profile? _surpriseTarget;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startsAt : _endsAt) ?? _startsAt ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startsAt = picked;
        // Keep end >= start.
        if (_endsAt != null && _endsAt!.isBefore(picked)) _endsAt = picked;
      } else {
        _endsAt = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Defensive: the DB enforces this too (events_time_order), but catch it
    // before the round-trip.
    if (_startsAt != null && _endsAt != null && _endsAt!.isBefore(_startsAt!)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).createEndBeforeStart)));
      return;
    }

    final id = await ref.read(createEventControllerProvider.notifier).create(
          title: _title.text.trim(),
          eventType: _type,
          description: _description.text.trim(),
          startsAt: _startsAt,
          endsAt: _endsAt,
          location: _location.text.trim(),
          surpriseTarget: _surpriseTarget?.id,
        );
    if (id != null && mounted) context.pop();
  }

  Future<void> _pickSurprise() async {
    final t = AppLocalizations.of(context);
    final friends = ref.read(friendListProvider).value ?? const [];
    final picked = await showMemberPicker(
      context,
      candidates: friends,
      emptyMessage: t.groupNoFriendsToAdd,
    );
    if (picked != null) setState(() => _surpriseTarget = picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createEventControllerProvider);
    final loading = state.isLoading;

    ref.listen(createEventControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(next.error!))));
      }
    });

    final t = AppLocalizations.of(context);
    String typeLabel(EventType type) => switch (type) {
          EventType.trip => t.eventTypeTrip,
          EventType.dinner => t.eventTypeDinner,
          EventType.birthday => t.eventTypeBirthday,
          EventType.meetup => t.eventTypeMeetup,
        };

    return Scaffold(
      appBar: AppBar(title: Text(t.createTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: t.createFieldTitle),
                  maxLength: 140,
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return t.createNeedTitle;
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(t.createFieldType,
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<EventType>(
                  segments: EventType.values
                      .map((type) =>
                          ButtonSegment(value: type, label: Text(typeLabel(type))))
                      .toList(),
                  selected: {_type},
                  onSelectionChanged: loading
                      ? null
                      : (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  textInputAction: TextInputAction.newline,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: t.createFieldDescription,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: t.createFieldStarts,
                        emptyText: t.createPickDate,
                        value: _startsAt,
                        onTap: loading ? null : () => _pickDate(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: t.createFieldEnds,
                        emptyText: t.createPickDate,
                        value: _endsAt,
                        onTap: loading ? null : () => _pickDate(isStart: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _location,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                      labelText: t.createFieldLocation,
                      prefixIcon: const Icon(Icons.place_outlined)),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),

                // Surprise target (optional).
                Text(t.createSurpriseLabel,
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                _SurpriseField(
                  target: _surpriseTarget,
                  onPick: loading ? null : _pickSurprise,
                  onClear:
                      loading ? null : () => setState(() => _surpriseTarget = null),
                ),
                if (_surpriseTarget != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.visibility_off_outlined,
                            size: 16, color: AppColors.yellow),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(t.createSurpriseHint,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.inkMuted)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: loading ? null : _submit,
                  child: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.createSubmit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The surprise-target chooser: a tappable field showing the chosen friend's
/// handle (or a prompt), with a clear action once one is set.
class _SurpriseField extends StatelessWidget {
  const _SurpriseField({
    required this.target,
    required this.onPick,
    required this.onClear,
  });
  final Profile? target;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: Icon(
            target == null ? Icons.card_giftcard_outlined : Icons.visibility_off,
            color: target == null ? null : AppColors.yellow,
          ),
          suffixIcon: target != null
              ? IconButton(
                  tooltip: t.createSurpriseClear,
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                )
              : null,
        ),
        child: Text(
          target?.handle ?? t.createSurpriseChoose,
          style: target == null
              ? TextStyle(color: Theme.of(context).hintColor)
              : null,
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.emptyText,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String emptyText;
  final DateTime? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? emptyText
        : '${value!.day.toString().padLeft(2, '0')}/'
            '${value!.month.toString().padLeft(2, '0')}/${value!.year}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
        ),
        child: Text(text,
            style: value == null
                ? TextStyle(color: Theme.of(context).hintColor)
                : null),
      ),
    );
  }
}
