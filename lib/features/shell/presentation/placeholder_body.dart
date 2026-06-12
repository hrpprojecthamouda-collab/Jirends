/// A consistent, on-theme empty/placeholder body used by the not-yet-built tabs.
/// Centered icon + message in muted ink. Keeps the stub screens tiny and uniform.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class PlaceholderBody extends StatelessWidget {
  const PlaceholderBody({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
