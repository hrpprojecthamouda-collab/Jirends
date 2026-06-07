/// EventMember — a row of public.event_members joined to the member's profile.
/// Membership IS visibility (the cardinal rule); if a member row reaches this
/// layer, the caller is allowed to see it. The enums mirror the PG enums
/// member_role and rsvp_status (json_serializable serializes by name).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/data/profile.dart';

part 'event_member.freezed.dart';
part 'event_member.g.dart';

enum MemberRole { organizer, member }

enum RsvpStatus { pending, going, maybe, declined }

@freezed
abstract class EventMember with _$EventMember {
  const EventMember._();

  const factory EventMember({
    required String userId,
    required MemberRole role,
    required RsvpStatus rsvp,
    required Profile profile,
  }) = _EventMember;

  factory EventMember.fromJson(Map<String, dynamic> json) =>
      _$EventMemberFromJson(json);

  bool get isOrganizer => role == MemberRole.organizer;
}
