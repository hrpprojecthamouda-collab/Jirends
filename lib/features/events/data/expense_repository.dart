/// ExpenseRepository — Tricount-style expenses for one event: log who paid
/// and who it's split between, then read a live minimum-transaction settle-up.
/// add_expense computes the equal split server-side and inserts the expense +
/// shares atomically; event_settle_up nets balances and pairs debtors with
/// creditors, also server-side. RLS scopes everything to event members; no
/// client visibility logic.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../auth/data/profile.dart';
import 'expense.dart';
import 'settle_up_transfer.dart';

class ExpenseRepository {
  ExpenseRepository(this._client);
  final SupabaseClient _client;

  Future<List<Expense>> fetchExpenses(String eventId) async {
    try {
      final rows = await _client
          .from('expenses')
          .select('*, payer:profiles!expenses_payer_id_fkey(*), '
              'shares:expense_shares(*, user:profiles!expense_shares_user_id_fkey(*))')
          .eq('event_id', eventId)
          .order('created_at', ascending: false);
      return rows.map(Expense.fromJson).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Stream<List<Expense>> watchExpenses(String eventId) {
    return _client
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .asyncMap((_) => fetchExpenses(eventId));
  }

  Future<void> addExpense(
    String eventId, {
    required String payerId,
    required String description,
    required int amountCents,
    required List<String> participantIds,
  }) async {
    try {
      await _client.rpc('add_expense', params: {
        'p_event': eventId,
        'p_payer': payerId,
        'p_description': description.trim(),
        'p_amount_cents': amountCents,
        'p_participant_ids': participantIds,
      });
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> deleteExpense(String expenseId) async {
    try {
      await _client.from('expenses').delete().eq('id', expenseId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<List<SettleUpTransfer>> fetchSettleUp(String eventId) async {
    try {
      final rows = await _client
          .rpc('event_settle_up', params: {'p_event': eventId}) as List;
      if (rows.isEmpty) return const [];

      final userIds = <String>{
        for (final r in rows) (r as Map)['from_user'] as String,
        for (final r in rows) (r as Map)['to_user'] as String,
      };
      final profileRows = await _client
          .from('profiles')
          .select()
          .inFilter('id', userIds.toList());
      final profilesById = {
        for (final p in profileRows.map(Profile.fromJson)) p.id: p,
      };

      return [
        for (final r in rows)
          SettleUpTransfer(
            fromUser: profilesById[(r as Map)['from_user'] as String]!,
            toUser: profilesById[r['to_user'] as String]!,
            amountCents: (r['amount_cents'] as num).toInt(),
          ),
      ];
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(ref.watch(supabaseClientProvider));
});
