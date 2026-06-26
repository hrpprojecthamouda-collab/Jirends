/// ExpenseShare — a row of public.expense_shares: one participant's equal-split
/// share of an expense, joined to their profile. Scoped to event members by
/// RLS; written only through the add_expense RPC, never inserted directly.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/data/profile.dart';

part 'expense_share.freezed.dart';
part 'expense_share.g.dart';

@freezed
abstract class ExpenseShare with _$ExpenseShare {
  const factory ExpenseShare({
    required String expenseId,
    required String userId,
    required int shareCents,
    required Profile user,
  }) = _ExpenseShare;

  factory ExpenseShare.fromJson(Map<String, dynamic> json) =>
      _$ExpenseShareFromJson(json);
}
