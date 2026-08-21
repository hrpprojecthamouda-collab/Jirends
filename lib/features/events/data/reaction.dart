/// Reaction — a row of public.reactions. Targets either the event itself
/// (commentId null) or a specific comment. Carries event_id for RLS scoping.
///
/// A user holds at most ONE reaction per target: picking another emoji
/// replaces it, picking the same one clears it.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/data/profile.dart';

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
    /// The reacting user's profile. Only populated by the queries that join it
    /// (the "who reacted" sheet); null on the realtime stream, which cannot
    /// join. Never used for visibility — profiles are world-readable and carry
    /// no event data.
    Profile? user,
  }) = _Reaction;

  factory Reaction.fromJson(Map<String, dynamic> json) =>
      _$ReactionFromJson(json);

  /// True for a reaction on the event itself (not on a comment).
  bool get isOnEvent => commentId == null;
}
