/// Crew — a Type-2 shared, visible group (mirrors public.crews). The owner adds
/// members and EVERY member can see the roster and that they belong. Contrast
/// [FriendGroup] (Type 1, owner-private). A crew is still NEVER a permission:
/// adding it to an event expands it into individual event_members rows at
/// add-time. `ownerId` lets the UI show crews you own as editable and crews you
/// merely belong to as read-only.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'crew.freezed.dart';
part 'crew.g.dart';

@freezed
abstract class Crew with _$Crew {
  const factory Crew({
    required String id,
    required String name,
    required String ownerId,
  }) = _Crew;

  factory Crew.fromJson(Map<String, dynamic> json) => _$CrewFromJson(json);
}
