/// Expense controllers: a live list of an event's expenses, a one-shot
/// settle-up read, and an action notifier for add/delete.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/expense.dart';
import '../data/expense_repository.dart';
import '../data/settle_up_transfer.dart';

final eventExpensesProvider =
    StreamProvider.family<List<Expense>, String>((ref, eventId) {
  return ref.watch(expenseRepositoryProvider).watchExpenses(eventId);
});

/// One-shot fetch of the minimum-transaction settle-up. A FutureProvider, not
/// a stream: it's derived from the expenses ledger via an RPC, not a single
/// table — the action controller invalidates it after every add/delete so it
/// stays in sync.
final settleUpProvider =
    FutureProvider.family<List<SettleUpTransfer>, String>((ref, eventId) {
  return ref.watch(expenseRepositoryProvider).fetchSettleUp(eventId);
});

class ExpenseActionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  ExpenseRepository get _repo => ref.read(expenseRepositoryProvider);

  void _refresh(String eventId) {
    ref.invalidate(eventExpensesProvider(eventId));
    ref.invalidate(settleUpProvider(eventId));
  }

  Future<bool> add(
    String eventId, {
    required String payerId,
    required String description,
    required int amountCents,
    required List<String> participantIds,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.addExpense(
          eventId,
          payerId: payerId,
          description: description,
          amountCents: amountCents,
          participantIds: participantIds,
        ));
    if (!state.hasError) _refresh(eventId);
    return !state.hasError;
  }

  Future<void> delete(String expenseId, String eventId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.deleteExpense(expenseId));
    if (!state.hasError) _refresh(eventId);
  }
}

final expenseActionsControllerProvider =
    AsyncNotifierProvider<ExpenseActionsController, void>(
        ExpenseActionsController.new);
