/// PollVote — a row of public.poll_votes. While the poll is open RLS returns
/// only the caller's own vote; after it closes, all members' votes are readable
/// (for the who-voted-what breakdown). [voter] is the joined profile, present
/// only in the post-close breakdown query.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/data/profile.dart';

part 'poll_vote.freezed.dart';
part 'poll_vote.g.dart';

@freezed
abstract class PollVote with _$PollVote {
  const factory PollVote({
    required String id,
    required String pollId,
    required String optionId,
    required String userId,
    Profile? voter,
  }) = _PollVote;

  factory PollVote.fromJson(Map<String, dynamic> json) =>
      _$PollVoteFromJson(json);
}

/// A plain (non-table) tally row from the poll_tallies RPC: votes per option.
class PollTally {
  const PollTally({required this.optionId, required this.votes});
  final String optionId;
  final int votes;

  factory PollTally.fromJson(Map<String, dynamic> json) => PollTally(
        optionId: json['option_id'] as String,
        votes: (json['votes'] as num).toInt(),
      );
}
