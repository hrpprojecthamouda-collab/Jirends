/// Settings — Slice 1 ships the working language switcher (fr/en/tn) and the
/// sign-out action (moved here from the events app bar). Persisting the locale
/// across launches and the rest of preferences are a later slice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';

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

    return Scaffold(
      appBar: AppBar(title: Text(t.navSettings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
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
                    activeColor: AppColors.violet,
                    title: Text(_localeLabel(locale)),
                  ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.coral),
            title: Text(t.settingsSignOut,
                style: const TextStyle(color: AppColors.coral)),
            onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
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
