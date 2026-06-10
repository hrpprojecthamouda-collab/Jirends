/// Comment — a row of public.comments joined to its author's profile. Scoped to
/// event members by RLS; no client-side visibility logic.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/data/profile.dart';

part 'comment.freezed.dart';
part 'comment.g.dart';

@freezed
abstract class Comment with _$Comment {
  const Comment._();

  const factory Comment({
    required String id,
    required String eventId,
    required String authorId,
    required String body,
    required DateTime createdAt,
    required Profile author,
    /// NULL for a top-level event comment; the root comment's id for a reply
    /// inside that comment's discussion (two-level only).
    String? parentId,
    /// The discussion's name. Only meaningful on a top-level (root) comment.
    String? threadTitle,
  }) = _Comment;

  factory Comment.fromJson(Map<String, dynamic> json) =>
      _$CommentFromJson(json);

  /// True for a top-level event comment (not a reply).
  bool get isRoot => parentId == null;
}
