// Regression test for the palette picker.
//
// The bug this guards against: colours are read from `AppColors`, a global
// static, so a widget writing `color: AppColors.bg` registers NO dependency on
// the Theme InheritedWidget. Rebuilding MaterialApp with a new ThemeData
// therefore does not mark such widgets dirty, and any screen already built
// keeps painting the OLD palette. Only screens that happen to watch
// paletteProvider themselves (i.e. Settings) appeared to work.
//
// main.dart fixes this by re-keying the subtree on the palette id so the whole
// tree rebuilds. These tests pin that behaviour, and would have caught the
// original bug: `switching the palette repaints a screen that does not watch
// the provider` fails without the KeyedSubtree.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jirends/core/theme/app_colors.dart';
import 'package:jirends/core/theme/app_palette.dart';
import 'package:jirends/core/theme/palette_controller.dart';

/// A deliberately "dumb" screen: it reads AppColors directly and never watches
/// paletteProvider or calls Theme.of — exactly like most widgets in the app.
class _DumbScreen extends StatelessWidget {
  const _DumbScreen();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('ground'),
      color: AppColors.bg,
      child: Container(key: const Key('brand'), color: AppColors.primary),
    );
  }
}

/// Mirrors how main.dart wires the app: theme from the palette, and the whole
/// MaterialApp re-keyed on the palette id.
///
/// The key has to sit on the MaterialApp itself. Keying a subtree *inside* it
/// does not work: WidgetsApp gives its Navigator a GlobalKey, so the route
/// subtree gets moved rather than rebuilt and the screens keep their old
/// colours. (That was the first attempted fix, and this test caught it.)
class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);
    return MaterialApp(
      key: ValueKey(palette.id),
      theme: ThemeData(brightness: palette.brightness),
      home: const _DumbScreen(),
    );
  }
}

// Find by key, not by type: MaterialApp inserts ColoredBoxes of its own.
Color _bgOf(WidgetTester tester) =>
    tester.widget<ColoredBox>(find.byKey(const Key('ground'))).color;

Color? _brandOf(WidgetTester tester) =>
    tester.widget<Container>(find.byKey(const Key('brand'))).color;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppColors.apply(kDefaultPalette);
  });

  testWidgets('switching the palette repaints a screen that does not watch '
      'the provider', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _Harness(),
      ),
    );

    expect(_bgOf(tester), kDefaultPalette.bg,
        reason: 'starts on the default palette');

    await container
        .read(paletteProvider.notifier)
        .select(AppPalette.sageSienna);
    await tester.pumpAndSettle();

    expect(_bgOf(tester), AppPalette.sageSienna.bg,
        reason: 'ground must follow the new palette');
    expect(_brandOf(tester), AppPalette.sageSienna.primary,
        reason: 'accents must follow too, not just the scaffold background');
  });

  testWidgets('every shipped palette actually applies', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _Harness(),
      ),
    );

    for (final p in kAppPalettes) {
      await container.read(paletteProvider.notifier).select(p);
      await tester.pumpAndSettle();
      expect(_bgOf(tester), p.bg, reason: '${p.label} ground');
      expect(_brandOf(tester), p.primary, reason: '${p.label} brand');
    }
  });

  test('the chosen palette is persisted and restored', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(paletteProvider.notifier)
        .select(AppPalette.apricotMorning);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('palette_id'), AppPalette.apricotMorning.id);

    // Simulate a cold start: forget the in-memory choice, then reload.
    AppColors.apply(kDefaultPalette);
    await loadSavedPalette();
    expect(AppColors.current.id, AppPalette.apricotMorning.id);
  });

  test('an unknown or missing saved id falls back to the default', () async {
    expect(paletteById(null).id, kDefaultPalette.id);
    expect(paletteById('retired_palette').id, kDefaultPalette.id);
  });
}
