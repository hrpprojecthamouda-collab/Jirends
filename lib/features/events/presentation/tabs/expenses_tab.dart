/// Expenses tab — Tricount-style: anyone logs what they paid and who it's
/// split between (equal split only); a "Settle up" card always shows the
/// live, minimum-transaction result computed server-side. Read-only — no
/// "mark as paid". RLS scopes everything to event members.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/event_detail_controller.dart';
import '../../application/expense_controller.dart';
import '../../data/expense.dart';
import '../../data/settle_up_transfer.dart';
import '../widgets/create_expense_sheet.dart';

String formatCents(int cents) => (cents / 100).toStringAsFixed(2);

class ExpensesTab extends ConsumerWidget {
  const ExpensesTab({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final myId = ref.watch(currentUserIdProvider);
    final members = ref.watch(eventMembersProvider(eventId)).value ?? const [];
    final expensesAsync = ref.watch(eventExpensesProvider(eventId));

    ref.listen(expenseActionsControllerProvider, (_, n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: members.isEmpty
            ? null
            : () => showCreateExpenseSheet(context,
                eventId: eventId, members: members),
        icon: const Icon(Icons.add),
        label: Text(t.expenseAdd),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(messageForError(e))),
        data: (expenses) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            _SettleUpCard(eventId: eventId),
            const SizedBox(height: 12),
            if (expenses.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t.expenseEmpty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.inkMuted)),
              )
            else
              for (final e in expenses)
                _ExpenseTile(expense: e, myId: myId),
          ],
        ),
      ),
    );
  }
}

class _SettleUpCard extends ConsumerWidget {
  const _SettleUpCard({required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final settleUpAsync = ref.watch(settleUpProvider(eventId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.settleUpTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            settleUpAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                    child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              ),
              error: (e, _) => Text(messageForError(e)),
              data: (transfers) => transfers.isEmpty
                  ? Text(t.settleUpEmpty,
                      style: const TextStyle(color: AppColors.inkMuted))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final tr in transfers) _TransferRow(transfer: tr),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.transfer});
  final SettleUpTransfer transfer;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        t.settleUpOwes(
          transfer.fromUser.handle ?? '…',
          transfer.toUser.handle ?? '…',
          formatCents(transfer.amountCents),
        ),
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({required this.expense, required this.myId});
  final Expense expense;
  final String? myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final canDelete =
        expense.createdBy == myId || _isOrganizer(ref, expense.eventId, myId);

    return Card(
      child: ListTile(
        title: Text(expense.description),
        subtitle: Text(
          '${expense.payer.handle ?? '…'} · ${t.expenseSplitCount(expense.shares.length)}',
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        trailing: canDelete
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.coral),
                tooltip: t.expenseDelete,
                onPressed: () => _confirmDelete(context, ref),
              )
            : Text(
                formatCents(expense.amountCents),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  bool _isOrganizer(WidgetRef ref, String eventId, String? userId) {
    if (userId == null) return false;
    final members = ref.read(eventMembersProvider(eventId)).value ?? const [];
    for (final m in members) {
      if (m.userId == userId) return m.isOrganizer;
    }
    return false;
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.expenseDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.expenseDelete,
                style: const TextStyle(color: AppColors.coral)),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref
          .read(expenseActionsControllerProvider.notifier)
          .delete(expense.id, expense.eventId);
    }
  }
}
