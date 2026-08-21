/// Localised short weekday names.
///
/// Deliberately NOT `DateFormat.E(locale)`: the app ships a custom `tn`
/// (Tunisian Derja) locale that has no ICU bundle, so intl would throw or
/// silently fall back to English for it. Reading the names out of the ARB files
/// keeps all three languages on the same footing, and matches how the rest of
/// the app formats dates (by hand — see short_time.dart).
library;

import '../../l10n/app_localizations.dart';

/// e.g. `Mon` / `Lun` / `Tnin`. Pass a LOCAL DateTime.
String weekdayShort(AppLocalizations t, DateTime d) => switch (d.weekday) {
      DateTime.monday => t.weekdayMon,
      DateTime.tuesday => t.weekdayTue,
      DateTime.wednesday => t.weekdayWed,
      DateTime.thursday => t.weekdayThu,
      DateTime.friday => t.weekdayFri,
      DateTime.saturday => t.weekdaySat,
      // DateTime.sunday is 7; anything else is impossible, but a switch on an
      // int needs a default.
      _ => t.weekdaySun,
    };
