/// App locale state. The Settings screen drives [localeProvider]; MaterialApp
/// reads it. Persistence (remembering the choice across launches) is deferred —
/// for now it resets to the device/English default each launch.
///
/// Tunisian ('tn') is a custom locale with no Material bundle, so the app
/// supplies its own strings while Material widgets fall back to English (handled
/// by localeResolutionCallback in main.dart).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The locales the app ships strings for, in display order.
const supportedAppLocales = <Locale>[
  Locale('en'),
  Locale('fr'),
  Locale('tn'),
];

class LocaleController extends Notifier<Locale> {
  @override
  Locale build() => const Locale('en');

  void setLocale(Locale locale) {
    if (supportedAppLocales.contains(locale)) state = locale;
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale>(
  LocaleController.new,
);
