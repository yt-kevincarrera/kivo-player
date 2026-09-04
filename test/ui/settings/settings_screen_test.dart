import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/ui/settings/settings_screen.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<ProviderContainer> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.0.0')),
  ]);
  addTearDown(c.dispose);
  await pumpLocalized(t, const SettingsScreen(), container: c, theme: KivoTheme.dark());
  return c;
}

void main() {
  testWidgets('root lists Acerca de and Restablecer', (t) async {
    await _pump(t);
    expect(find.text(_l10n.settingsAboutTitle), findsOneWidget);
    // The list grew past one screen (Copia de seguridad added a row) —
    // the reset tile below it needs a scroll to be built at all.
    await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await t.pump();
    expect(find.text(_l10n.settingsResetAllTitle), findsOneWidget);
  });

  testWidgets('tapping Acerca de navigates to the about screen', (t) async {
    await _pump(t);
    await t.tap(find.text(_l10n.settingsAboutTitle));
    await t.pumpAndSettle();
    expect(find.text('Kivo'), findsWidgets);
    expect(find.textContaining('1.0.0'), findsOneWidget);
  });

  testWidgets('reset asks for confirmation, then restores defaults', (t) async {
    final c = await _pump(t);
    // Put a non-default value.
    final n = c.read(settingsProvider.notifier);
    n.set(c.read(settingsProvider).copyWith(accentColor: 0xFF5B9BE8));
    await t.pump();
    // Same as above: scroll the reset tile into view before tapping it.
    await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await t.pump();
    await t.tap(find.text(_l10n.settingsResetAllTitle));
    await t.pumpAndSettle();
    expect(find.text(_l10n.settingsResetAction), findsOneWidget); // dialog confirm button
    await t.tap(find.text(_l10n.settingsResetAction).last);
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).accentColor, KivoSettings.defaults().accentColor);
  });

  testWidgets('root lists Reproducción y gestos and navigates', (t) async {
    await _pump(t); // existing helper in that file
    expect(find.text(_l10n.settingsPlaybackGesturesTitle), findsOneWidget);
    await t.tap(find.text(_l10n.settingsPlaybackGesturesTitle));
    await t.pumpAndSettle();
    expect(find.text(_l10n.settingsGesturesGroupDoubleTap.toUpperCase()),
        findsWidgets); // a group label on the section (rendered upper-case)
  });

  testWidgets('root lists Interfaz and navigates', (t) async {
    await _pump(t);
    expect(find.text(_l10n.settingsInterfaceTitle), findsOneWidget);
    await t.tap(find.text(_l10n.settingsInterfaceTitle));
    await t.pumpAndSettle();
    expect(find.text(_l10n.settingsInterfaceGroupControls.toUpperCase()),
        findsWidgets); // an uppercased group label on the section
  });

  testWidgets('root lists Reproducción avanzada and navigates', (t) async {
    await _pump(t);
    expect(find.text(_l10n.settingsAdvancedPlaybackTitle), findsOneWidget);
    await t.tap(find.text(_l10n.settingsAdvancedPlaybackTitle));
    await t.pumpAndSettle();
    expect(find.text(_l10n.settingsAdvancedGroupContinueWatching.toUpperCase()),
        findsWidgets); // an uppercased group label
  });
}
