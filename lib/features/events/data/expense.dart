/// Expense model — mirrors public.expenses, with its equal-split shares
/// embedded. Amounts are integer cents (never float) to avoid rounding error
/// on money. Scoped to event members by RLS; no client visibility logic.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/data/profile.dart';
import 'expense_share.dart';

part 'expense.freezed.dart';
part 'expense.g.dart';

@freezed
abstract class Expense with _$Expense {
  const factory Expense({
    required String id,
    required String eventId,
    required String payerId,
    required String description,
    required int amountCents,
    required String createdBy,
    required DateTime createdAt,
    /// The payer's profile, joined for display.
    required Profile payer,
    /// Equal-split shares for this expense, one per participant.
    @Default([]) List<ExpenseShare> shares,
  }) = _Expense;

  factory Expense.fromJson(Map<String, dynamic> json) =>
      _$ExpenseFromJson(json);
}
