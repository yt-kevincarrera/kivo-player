import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/l10n/generated/app_localizations.dart';

/// Mounts [child] under a localized `MaterialApp`, the way `app.dart` does
/// (delegates + supported locales), so widgets that call `context.l10n` work
/// in tests without depending on the real `KivoApp`.
///
/// Pass [container] to also wrap in an `UncontrolledProviderScope` — the
/// usual case for anything reading `settingsProvider` or similar. Without
/// it, [child] is mounted directly (for widgets with no Riverpod deps).
Future<void> pumpLocalized(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('es'),
  ProviderContainer? container,
  ThemeData? theme,
}) async {
  final app = MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: theme,
    home: child,
  );
  await tester.pumpWidget(
    container == null
        ? app
        : UncontrolledProviderScope(container: container, child: app),
  );
}

/// The generated `AppLocalizations` for [locale], for asserting on keys
/// directly (e.g. `l10nFor(const Locale('en')).settingsLanguage`) without
/// needing a `BuildContext`.
AppLocalizations l10nFor(Locale locale) => lookupAppLocalizations(locale);
