/// FriendGroup — a Type-1 selection group (mirrors public.friend_groups). These
/// are OWNER-PRIVATE: a personal shortcut for adding several friends to an event
/// at once. Members never know they're in one. A group is NEVER a permission —
/// it expands into individual event_members rows at add-time. Contrast [Crew]
/// (Type 2, shared & visible).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'friend_group.freezed.dart';
part 'friend_group.g.dart';

@freezed
abstract class FriendGroup with _$FriendGroup {
  const factory FriendGroup({
    required String id,
    required String name,
  }) = _FriendGroup;

  factory FriendGroup.fromJson(Map<String, dynamic> json) =>
      _$FriendGroupFromJson(json);
}
