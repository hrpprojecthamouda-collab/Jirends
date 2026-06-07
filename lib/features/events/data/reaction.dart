/// Reaction — a row of public.reactions. Targets either the event itself
/// (commentId null) or a specific comment. Carries event_id for RLS scoping.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'reaction.freezed.dart';
part 'reaction.g.dart';

@freezed
abstract class Reaction with _$Reaction {
  const Reaction._();

  const factory Reaction({
    required String id,
    required String eventId,
    String? commentId,
    required String userId,
    required String emoji,
  }) = _Reaction;

  factory Reaction.fromJson(Map<String, dynamic> json) =>
      _$ReactionFromJson(json);

  /// True for a reaction on the event itself (not on a comment).
  bool get isOnEvent => commentId == null;
}
