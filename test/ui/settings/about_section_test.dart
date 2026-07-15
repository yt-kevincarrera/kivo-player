import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_checker.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/ui/settings/sections/about_section.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('shows the real version and the manual check → up to date', (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.2.3')),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker()..throwsNull = false),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: AboutSection())));
    await tester.pumpAndSettle();
    expect(find.text('Versión 1.2.3'), findsOneWidget);
    expect(find.text('Buscar actualizaciones'), findsOneWidget);
  });

  testWidgets('toggle flips autoCheckUpdates', (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.0.0')),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker()),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: AboutSection())));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).autoCheckUpdates, true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).autoCheckUpdates, false);
  });
}
