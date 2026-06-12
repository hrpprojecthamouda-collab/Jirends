/// PollOption — a row of public.poll_options: one choice in a poll. `value` is
/// the typed payload used to APPLY a winner to the event on close: day polls
/// store 'YYYY-MM-DD', time polls 'HH:mm'; general/place options have none
/// (a place option's label IS its value). Scoped by RLS to event members.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'poll_option.freezed.dart';
part 'poll_option.g.dart';

@freezed
abstract class PollOption with _$PollOption {
  const factory PollOption({
    required String id,
    required String pollId,
    required String label,
    required int position,
    String? value,
  }) = _PollOption;

  factory PollOption.fromJson(Map<String, dynamic> json) =>
      _$PollOptionFromJson(json);
}
