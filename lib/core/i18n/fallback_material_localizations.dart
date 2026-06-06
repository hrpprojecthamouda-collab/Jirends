/// Tunisian ('tn') is a custom locale with no Material/Cupertino/Widgets bundle
/// in flutter_localizations. Our own AppLocalizations serves the 'tn' app
/// strings, but the framework's Material widgets (date picker, tooltips, etc.)
/// would throw for 'tn'. These delegates map 'tn' -> 'en' for the framework
/// bundles only, so Material widgets render in English while the app text stays
/// Tunisian. For every other locale they defer to the real global delegates.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const _fallback = Locale('en');

Locale _mapTn(Locale locale) => locale.languageCode == 'tn' ? _fallback : locale;

class _MaterialFallbackDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _MaterialFallbackDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(_mapTn(locale));
  @override
  bool shouldReload(_) => false;
}

class _CupertinoFallbackDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CupertinoFallbackDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(_mapTn(locale));
  @override
  bool shouldReload(_) => false;
}

class _WidgetsFallbackDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _WidgetsFallbackDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(_mapTn(locale));
  @override
  bool shouldReload(_) => false;
}

/// The framework localization delegates, with 'tn' folded onto 'en'.
const tnAwareFrameworkDelegates = <LocalizationsDelegate<dynamic>>[
  _MaterialFallbackDelegate(),
  _CupertinoFallbackDelegate(),
  _WidgetsFallbackDelegate(),
];
