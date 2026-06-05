/// Profile model — mirrors public.profiles. The (nickname, tagline) pair is the
/// user's handle, rendered as `nickname#tagline`. Both are null until the user
/// completes onboarding.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

@freezed
abstract class Profile with _$Profile {
  const Profile._();

  const factory Profile({
    required String id,
    String? nickname,
    String? tagline,
    String? avatarUrl,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);

  /// True once both handle parts are set (onboarding complete).
  bool get hasHandle => nickname != null && tagline != null;

  /// The display handle, e.g. `Sparrow#TheCrew`, or null if not set.
  String? get handle => hasHandle ? '$nickname#$tagline' : null;
}
