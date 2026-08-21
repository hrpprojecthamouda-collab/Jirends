/// UserAvatar — one person's face: their photo if they've set one, their
/// initials if they haven't.
///
/// Every people-avatar in the app goes through this, so a photo appears
/// everywhere the moment it's uploaded and there is exactly one place that
/// knows what to do when the image fails to load. Group and activity circles
/// (a padlock, a bolt) are NOT people and deliberately don't use it.
///
/// A missing photo is the normal case, not an error state — nobody has one
/// until they choose one — so the initials fallback is silent, and so is a
/// broken URL.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/data/profile.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.profile,
    this.radius = 20,
    this.background,
    this.foreground,
  });

  /// Null renders the '?' placeholder — a member whose profile hasn't loaded.
  final Profile? profile;
  final double radius;

  /// Tint for the initials circle. The photo covers it entirely, so these only
  /// show when there is no photo.
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final url = profile?.avatarUrl;
    final side = radius * 2;

    return SizedBox(
      width: side,
      height: side,
      child: ClipOval(
        child: url == null || url.isEmpty
            ? _initials(context)
            : Image.network(
                url,
                width: side,
                height: side,
                fit: BoxFit.cover,
                // Offline, deleted object, bad URL — fall back to the initials
                // rather than to a broken-image glyph.
                errorBuilder: (_, _, _) => _initials(context),
                // No spinner: at avatar size it would be more visual noise than
                // the picture it's standing in for. Hold the initials instead,
                // so the circle never collapses or flashes empty.
                frameBuilder: (_, child, frame, wasSyncLoaded) {
                  if (wasSyncLoaded || frame != null) return child;
                  return _initials(context);
                },
              ),
      ),
    );
  }

  Widget _initials(BuildContext context) {
    return ColoredBox(
      color: background ?? AppColors.primary.withValues(alpha: .18),
      child: Center(
        child: Text(
          profile?.initials ?? '?',
          style: TextStyle(
            // Tracks the circle rather than the text theme: these have to fit
            // inside a fixed diameter, from a 16px app-bar button to a 44px
            // profile header.
            fontSize: radius * 0.7,
            fontWeight: FontWeight.w700,
            color: foreground ?? AppColors.primary,
          ),
        ),
      ),
    );
  }
}
