/// PollOption — a row of public.poll_options: one choice in a poll. Labels only
/// (no typed payload). Scoped by RLS to event members.
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
  }) = _PollOption;

  factory PollOption.fromJson(Map<String, dynamic> json) =>
      _$PollOptionFromJson(json);
}
