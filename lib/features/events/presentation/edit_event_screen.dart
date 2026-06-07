/// Edit an event's core fields (title, description, dates, location). Organizer
/// only — the edit entry point is shown only to organizers and the DB enforces
/// it regardless (events_update_organizer). Type, status, and the surprise
/// target are NOT edited here (type is immutable for a created event; status has
/// its own workflow on the Overview tab; changing a surprise target post-hoc is
/// deliberately out of scope). On success we pop back to the detail screen,
/// whose header refreshes via the invalidated single-event provider.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/event_list_controller.dart';
import '../data/event.dart';

class EditEventScreen extends ConsumerStatefulWidget {
  const EditEventScreen({super.key, required this.event});
  final Event event;

  @override
  ConsumerState<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends ConsumerState<EditEventScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late DateTime? _startsAt;
  late DateTime? _endsAt;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e.title);
    _description = TextEditingController(text: e.description ?? '');
    _location = TextEditingController(text: e.location ?? '');
    _startsAt = e.startsAt?.toLocal();
    _endsAt = e.endsAt?.toLocal();
  }

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
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startsAt = picked;
        if (_endsAt != null && _endsAt!.isBefore(picked)) _endsAt = picked;
      } else {
        _endsAt = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startsAt != null && _endsAt != null && _endsAt!.isBefore(_startsAt!)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).createEndBeforeStart)));
      return;
    }
    final desc = _description.text.trim();
    final loc = _location.text.trim();
    final ok = await ref.read(editEventControllerProvider.notifier).save(
          widget.event.id,
          title: _title.text.trim(),
          description: desc.isEmpty ? null : desc,
          clearDescription: desc.isEmpty,
          startsAt: _startsAt,
          clearStartsAt: _startsAt == null,
          endsAt: _endsAt,
          clearEndsAt: _endsAt == null,
          location: loc.isEmpty ? null : loc,
          clearLocation: loc.isEmpty,
        );
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final loading = ref.watch(editEventControllerProvider).isLoading;

    ref.listen(editEventControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(next.error!))));
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(t.editTitle)),
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
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? t.createNeedTitle : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
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
                        onClear: loading || _startsAt == null
                            ? null
                            : () => setState(() => _startsAt = null),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: t.createFieldEnds,
                        emptyText: t.createPickDate,
                        value: _endsAt,
                        onTap: loading ? null : () => _pickDate(isStart: false),
                        onClear: loading || _endsAt == null
                            ? null
                            : () => setState(() => _endsAt = null),
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
                  onFieldSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: loading ? null : _save,
                  child: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.editSave),
                ),
              ],
            ),
          ),
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
    required this.onClear,
  });

  final String label;
  final String emptyText;
  final DateTime? value;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

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
          suffixIcon: value != null
              ? IconButton(icon: const Icon(Icons.close), onPressed: onClear)
              : null,
        ),
        child: Text(text,
            style: value == null
                ? TextStyle(color: Theme.of(context).hintColor)
                : null),
      ),
    );
  }
}
