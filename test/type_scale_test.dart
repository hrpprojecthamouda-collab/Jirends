/// The type scale is corrected for Baloo 2 being optically smaller than the
/// Roboto the Material scale was drawn for (see AppTheme._opticalScale).
///
/// These sizes are asserted through a real MaterialApp rather than off
/// `AppTheme.of(...).textTheme`, because that is the only place they exist:
/// ThemeData's textTheme carries colours with NULL font sizes, and the numbers
/// are merged in from Typography geometry by ThemeData.localize at build time.
/// A first attempt scaled the textTheme instead and shipped an app that
/// crashed on launch — that is what this test exists to catch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jirends/core/theme/app_palette.dart';
import 'package:jirends/core/theme/app_theme.dart';

/// Material's unscaled 2021 sizes, for reference in the expectations below.
const _base = <String, double>{
  'headlineSmall': 24,
  'titleLarge': 22,
  'titleMedium': 16,
  'bodyLarge': 16,
  'bodyMedium': 14,
  'bodySmall': 12,
  'labelLarge': 14,
  'labelMedium': 12,
  'labelSmall': 11,
};

Future<TextTheme> _resolved(WidgetTester tester, AppPalette palette) async {
  late TextTheme resolved;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.of(palette),
    home: Builder(builder: (context) {
      resolved = Theme.of(context).textTheme;
      return const SizedBox.shrink();
    }),
  ));
  return resolved;
}

void main() {
  testWidgets('body and label sizes carry the optical correction',
      (tester) async {
    final t = await _resolved(tester, kDefaultPalette);

    // 1.15 = Roboto's x-height (0.528em) over Baloo 2's (0.460em).
    expect(t.bodyLarge!.fontSize, closeTo(_base['bodyLarge']! * 1.15, 0.01));
    expect(t.bodyMedium!.fontSize, closeTo(_base['bodyMedium']! * 1.15, 0.01));
    expect(t.bodySmall!.fontSize, closeTo(_base['bodySmall']! * 1.15, 0.01));
    expect(t.labelLarge!.fontSize, closeTo(_base['labelLarge']! * 1.15, 0.01));
    expect(t.labelMedium!.fontSize, closeTo(_base['labelMedium']! * 1.15, 0.01));
    expect(t.labelSmall!.fontSize, closeTo(_base['labelSmall']! * 1.15, 0.01));
    expect(t.titleLarge!.fontSize, closeTo(_base['titleLarge']! * 1.15, 0.01));
    expect(t.titleMedium!.fontSize, closeTo(_base['titleMedium']! * 1.15, 0.01));
  });

  testWidgets('nothing readable is left below a 12sp floor', (tester) async {
    final t = await _resolved(tester, kDefaultPalette);
    // labelSmall is the smallest role we use (section captions, timestamps,
    // voter counts). Uncorrected it was 11 — under the size at which a caption
    // stays comfortably readable on a phone.
    expect(t.labelSmall!.fontSize, greaterThanOrEqualTo(12));
  });

  testWidgets('Roboto letter-spacing is not inherited',
      (tester) async {
    // bodyLarge ships +0.5 tracking tuned for Roboto. Baloo 2 already carries
    // generous sidebearings, so that is 6.5% of every line spent on air —
    // whole words pushed onto the next line in an event description.
    final t = await _resolved(tester, kDefaultPalette);
    for (final style in [t.bodyLarge, t.bodyMedium, t.bodySmall, t.titleLarge]) {
      expect(style!.letterSpacing, 0);
    }
  });

  testWidgets('the event title is pinned, not scaled', (tester) async {
    final t = await _resolved(tester, kDefaultPalette);
    // Set outright at 28: Baloo 2 is wide, and 24 * 1.15 = 27.6 is fine but
    // the pin is deliberate — the title is tuned to the width of a phone, so
    // it must not drift when the correction factor is retuned.
    expect(t.headlineSmall!.fontSize, 28);
    expect(t.headlineSmall!.fontWeight, FontWeight.w800);
  });

  testWidgets('every palette builds a usable theme', (tester) async {
    // The crash this suite exists for happened at theme-construction time and
    // affected all palettes equally, so check each one actually renders.
    for (final p in kAppPalettes) {
      final t = await _resolved(tester, p);
      expect(t.bodyLarge!.fontSize, isNotNull, reason: p.id);
    }
  });
}
