/// showEventOverlaySheet — the standard "panel over the event page" used by
/// everything that used to be its own tab (Polls, the RSVP roster, the toolbox
/// destinations).
///
/// Covers 80% of the height and 95% of the width, scrolls internally, and
/// carries a drag handle: dismiss by dragging down or tapping outside. Rounded
/// on all corners and inset from the bottom so it reads as a floating panel
/// rather than a bottom sheet welded to the screen edge.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Fraction of the screen the panel covers.
const _kHeightFactor = 0.80;
const _kWidthFactor = 0.95;

Future<T?> showEventOverlaySheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) async {
  final result = await showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // The panel paints its own surface; keep the sheet chrome out of the way.
    builder: (context) => _OverlayPanel(title: title, child: child),
  );

  // Closing a modal route restores focus to the page underneath. On the event
  // page that lands on the comment compose field, which pops the keyboard open
  // as if it had been tapped. Drop focus explicitly — once now, and once after
  // the next frame, because the route's own focus restoration runs after this
  // await completes and would otherwise re-take it.
  FocusManager.instance.primaryFocus?.unfocus();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FocusManager.instance.primaryFocus?.unfocus();
  });

  return result;
}

class _OverlayPanel extends StatelessWidget {
  const _OverlayPanel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        // Inset from the bottom so all four corners are visible — this is a
        // floating panel, not a sheet attached to the screen edge.
        padding: EdgeInsets.only(bottom: size.height * 0.02),
        child: SizedBox(
          width: size.width * _kWidthFactor,
          height: size.height * _kHeightFactor,
          child: Material(
            // Same ground as the event page behind it, so opening a panel
            // feels like sliding a sheet of the same paper up rather than
            // switching to a different surface.
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Drag handle — the whole header is draggable so the gesture
                // works even when the body is a scrollable that would
                // otherwise swallow the drag.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) > 0) Navigator.of(context).pop();
                  },
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.inkMuted,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title.toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: AppColors.inkMuted,
                                      letterSpacing: 1.1,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            InkWell(
                              onTap: () => Navigator.of(context).pop(),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close,
                                    size: 18, color: AppColors.inkMuted),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 1, color: AppColors.outline),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
