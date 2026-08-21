/// Create-expense bottom sheet. Description + amount (parsed to integer
/// cents), a single payer (defaults to the caller, reuses showMemberPicker),
/// and an inline multi-select checklist of "who's concerned" (defaults to
/// everyone) — the amount divides evenly among them server-side. Owns its
/// text controllers in State so they're disposed safely.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/data/profile.dart';
import '../../application/expense_controller.dart';
import '../../data/event_member.dart';
import '../../../groups/presentation/member_picker.dart';

Future<void> showCreateExpenseSheet(
  BuildContext context, {
  required String eventId,
  required List<EventMember> members,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _CreateExpenseSheet(eventId: eventId, members: members),
  );
}

class _CreateExpenseSheet extends ConsumerStatefulWidget {
  const _CreateExpenseSheet({required this.eventId, required this.members});
  final String eventId;
  final List<EventMember> members;

  @override
  ConsumerState<_CreateExpenseSheet> createState() =>
      _CreateExpenseSheetState();
}

class _CreateExpenseSheetState extends ConsumerState<_CreateExpenseSheet> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  String? _payerId;
  late Set<String> _participantIds;
  String? _error;

  @override
  void initState() {
    super.initState();
    final myId = ref.read(currentUserIdProvider);
    _payerId = myId ?? widget.members.firstOrNull?.userId;
    _participantIds = widget.members.map((m) => m.userId).toSet();
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Profile? _profileFor(String userId) =>
      widget.members.firstWhereOrNull((m) => m.userId == userId)?.profile;

  Future<void> _pickPayer() async {
    final picked = await showMemberPicker(
      context,
      candidates: [for (final m in widget.members) m.profile],
      emptyMessage: '',
    );
    if (picked != null) setState(() => _payerId = picked.id);
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final description = _description.text.trim();
    if (description.isEmpty) {
      setState(() => _error = t.expenseNeedDescription);
      return;
    }
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      setState(() => _error = t.expenseNeedAmount);
      return;
    }
    if (_payerId == null) {
      setState(() => _error = t.expenseNeedPayer);
      return;
    }
    if (_participantIds.isEmpty) {
      setState(() => _error = t.expenseNeedParticipants);
      return;
    }
    final amountCents = (amount * 100).round();

    final ok = await ref.read(expenseActionsControllerProvider.notifier).add(
          widget.eventId,
          payerId: _payerId!,
          description: description,
          amountCents: amountCents,
          participantIds: _participantIds.toList(),
        );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final loading = ref.watch(expenseActionsControllerProvider).isLoading;
    final payerHandle = _payerId == null ? null : _profileFor(_payerId!)?.handle;

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
            Text(t.expenseAdd, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            TextField(
              controller: _description,
              maxLength: 140,
              decoration: InputDecoration(
                  labelText: t.expenseDescription, counterText: ''),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
              ],
              decoration: InputDecoration(labelText: t.expenseAmount),
            ),
            const SizedBox(height: 16),

            Text(t.expensePayer, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: _pickPayer,
              child: Text(payerHandle ?? t.expensePayer),
            ),
            const SizedBox(height: 16),

            Text(t.expenseSplitWith,
                style: Theme.of(context).textTheme.labelLarge),
            for (final m in widget.members)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _participantIds.contains(m.userId),
                title: Text(m.profile.handle ?? '…'),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _participantIds.add(m.userId);
                  } else {
                    _participantIds.remove(m.userId);
                  }
                }),
              ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!,
                    style: TextStyle(color: AppColors.coral)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: loading ? null : _submit,
              child: loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.expenseAdd),
            ),
          ],
        ),
      ),
    );
  }
}

extension on List<EventMember> {
  EventMember? get firstOrNull => isEmpty ? null : first;
  EventMember? firstWhereOrNull(bool Function(EventMember) test) {
    for (final m in this) {
      if (test(m)) return m;
    }
    return null;
  }
}
