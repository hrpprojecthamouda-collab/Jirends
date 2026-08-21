/// The description editor is the one event field with a page of its own, and
/// the one that can lose a paragraph of somebody's typing. These cover what it
/// hands back to the caller — including the distinction between "backed out"
/// (null, change nothing) and "saved empty" (clear the description).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jirends/core/i18n/fallback_material_localizations.dart';
import 'package:jirends/core/theme/app_palette.dart';
import 'package:jirends/core/theme/app_theme.dart';
import 'package:jirends/l10n/app_localizations.dart';
import 'package:jirends/features/events/presentation/widgets/description_editor_sheet.dart';

/// Pumps a screen with one button that opens the editor, and records whatever
/// the editor resolves to. `result.value` stays [_unset] until it closes.
const _unset = Object();

Future<ValueNotifier<Object?>> _open(
  WidgetTester tester, {
  String initial = '',
}) async {
  final result = ValueNotifier<Object?>(_unset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.of(kDefaultPalette),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...tnAwareFrameworkDelegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result.value =
                await showDescriptionEditor(context, initial: initial);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('the header carries back, title, undo and save', (tester) async {
    await _open(tester);

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.text('All good!'), findsOneWidget);
  });

  testWidgets('undo is dead until something has been typed', (tester) async {
    await _open(tester, initial: 'before');

    IconButton undoButton() => tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Icons.undo), matching: find.byType(IconButton)));

    expect(undoButton().onPressed, isNull,
        reason: 'nothing typed yet, so there is nothing to step back to');

    await tester.enterText(find.byType(TextField), 'before and after');
    // UndoHistory throttles: an edit only becomes an undoable step ~500ms after
    // you stop typing, so a burst of keystrokes is one step and not forty.
    await tester.pump(const Duration(milliseconds: 600));
    expect(undoButton().onPressed, isNotNull);

    // Stepping back returns the field to what it held before that edit.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(find.text('before'), findsOneWidget);
  });

  testWidgets('saving hands back the trimmed text', (tester) async {
    final result = await _open(tester, initial: 'old');

    await tester.enterText(find.byType(TextField), '  a new description  ');
    await tester.tap(find.text('All good!'));
    await tester.pumpAndSettle();

    expect(result.value, 'a new description');
  });

  testWidgets('saving an empty box means CLEAR, not cancel', (tester) async {
    final result = await _open(tester, initial: 'old');

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('All good!'));
    await tester.pumpAndSettle();

    // Empty string, NOT null: the caller has to be able to tell "they wiped
    // the description" apart from "they backed out".
    expect(result.value, '');
  });

  testWidgets('backing out untouched closes without asking', (tester) async {
    final result = await _open(tester, initial: 'old');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(result.value, isNull);
  });

  testWidgets('backing out with edits asks before throwing them away',
      (tester) async {
    final result = await _open(tester, initial: 'old');
    await tester.enterText(find.byType(TextField), 'a paragraph of typing');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // Cancel: still editing, nothing handed back, the typing survives.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result.value, same(_unset));
    expect(find.text('a paragraph of typing'), findsOneWidget);

    // Discard: closes, and the caller is told nothing was saved.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(result.value, isNull);
  });
}
