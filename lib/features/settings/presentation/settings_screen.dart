/// Settings — the colour-palette picker, the language switcher (fr/en/tn), and
/// the sign-out action. The palette choice persists across launches; the locale
/// still resets each launch (a later slice).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/palette_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/presentation/widgets/dev_account_switcher.dart';
import '../../auth/presentation/widgets/sign_out_tile.dart';

/// The display name to show for each supported locale, in its own language.
String _localeLabel(Locale l) => switch (l.languageCode) {
      'fr' => 'Français',
      'tn' => 'Tounsi',
      _ => 'English',
    };

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final current = ref.watch(localeProvider);
    final palette = ref.watch(paletteProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.navSettings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(t.settingsTheme),
          for (final p in kAppPalettes)
            _PaletteTile(
              palette: p,
              selected: p.id == palette.id,
              onTap: () => ref.read(paletteProvider.notifier).select(p),
            ),
          const Divider(),
          _SectionHeader(t.settingsLanguage),
          RadioGroup<Locale>(
            groupValue: current,
            onChanged: (l) {
              if (l != null) ref.read(localeProvider.notifier).setLocale(l);
            },
            child: Column(
              children: [
                for (final locale in supportedAppLocales)
                  RadioListTile<Locale>(
                    value: locale,
                    activeColor: AppColors.primary,
                    title: Text(_localeLabel(locale)),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: DevAccountSwitcher(),
          ),
          const Divider(),
          const SignOutTile(),
        ],
      ),
    );
  }
}

/// One selectable palette. Renders in ITS OWN colours rather than the active
/// theme's, so the row is a preview of what you'd get — ground, card, brand and
/// the accents that carry event/status meaning.
class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.palette,
    required this.selected,
    required this.onTap,
  });
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Ground + card + brand, stacked the way the app layers them.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.outline),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: palette.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      palette.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: palette.ink,
                          ),
                    ),
                    const SizedBox(height: 6),
                    // The six meaning-carrying accents.
                    Row(
                      children: [
                        for (final c in [
                          palette.yellow,
                          palette.blue,
                          palette.violet,
                          palette.teal,
                          palette.coral,
                        ])
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: palette.primary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.inkMuted,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}
