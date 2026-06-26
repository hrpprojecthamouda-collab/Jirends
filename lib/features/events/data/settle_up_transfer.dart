/// SettleUpTransfer — one row returned by the event_settle_up RPC: the
/// minimum-transaction suggestion that `fromUser` pays `toUser` amountCents.
/// Read-only and always computed live from the expense ledger.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/data/profile.dart';

part 'settle_up_transfer.freezed.dart';

@freezed
abstract class SettleUpTransfer with _$SettleUpTransfer {
  const factory SettleUpTransfer({
    required Profile fromUser,
    required Profile toUser,
    required int amountCents,
  }) = _SettleUpTransfer;
}
