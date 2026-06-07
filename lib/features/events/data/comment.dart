/// Comment — a row of public.comments joined to its author's profile. Scoped to
/// event members by RLS; no client-side visibility logic.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/data/profile.dart';

part 'comment.freezed.dart';
part 'comment.g.dart';

@freezed
abstract class Comment with _$Comment {
  const factory Comment({
    required String id,
    required String eventId,
    required String authorId,
    required String body,
    required DateTime createdAt,
    required Profile author,
  }) = _Comment;

  factory Comment.fromJson(Map<String, dynamic> json) =>
      _$CommentFromJson(json);
}
