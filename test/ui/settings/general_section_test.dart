import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/l10n/generated/app_localizations.dart';
import 'package:kivo_player/ui/settings/sections/general_section.dart';
import 'package:kivo_player/ui/settings/widgets/setting_tiles.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

Future<ProviderContainer> _pump(WidgetTester t, {Locale locale = const Locale('es')}) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await pumpLocalized(
    t,
    const GeneralSettingsSection(),
    locale: locale,
    container: c,
    theme: KivoTheme.dark(),
  );
  return c;
}

void main() {
  testWidgets('changing the theme segment persists themeMode', (t) async {
    final c = await _pump(t);
    await t.tap(find.text('Claro'));
    await t.pump();
    expect(c.read(settingsProvider).themeMode, 'light');
  });

  testWidgets('toggling haptics persists hapticsOnGestures', (t) async {
    final c = await _pump(t);
    final before = c.read(settingsProvider).hapticsOnGestures;
    await t.tap(find.byType(Switch));
    await t.pump();
    expect(c.read(settingsProvider).hapticsOnGestures, !before);
  });

  testWidgets('choosing an accent preset persists accentColor', (t) async {
    final c = await _pump(t);
    await t.tap(find.byKey(const ValueKey('accent-preset-1')));
    await t.pump();
    expect(c.read(settingsProvider).accentColor, kAccentPresets[1]);
  });

  testWidgets('choosing English persists locale and re-renders the row in English', (t) async {
    // Mirrors app.dart's MaterialApp.locale wiring (settingsProvider.locale
    // drives `locale:`) instead of pumpLocalized's fixed locale, so the
    // round-trip through the real pipe — tap -> persist -> MaterialApp
    // re-locales -> row re-renders in the new language — is actually
    // exercised, not just the persistence half of it.
    final s = await SettingsService.load(InMemorySettingsStore());
    // Pin the starting locale to 'es' explicitly rather than leaving it at
    // the 'system' default — the test harness's own default locale is
    // environment-dependent, and this test needs a known starting language.
    await s.update(s.current.copyWith(locale: 'es'));
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: Consumer(builder: (context, ref, _) {
        final localeSetting = ref.watch(settingsProvider.select((s) => s.locale));
        return MaterialApp(
          theme: KivoTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: localeSetting == 'system' ? null : Locale(localeSetting),
          home: const GeneralSettingsSection(),
        );
      }),
    ));

    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Language'), findsNothing);

    await t.tap(find.text('English'));
    await t.pumpAndSettle();

    expect(c.read(settingsProvider).locale, 'en');
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Idioma'), findsNothing);
  });
}
