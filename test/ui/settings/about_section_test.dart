import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/platform/interfaces/app_installer.dart';
import 'package:kivo_player/ui/settings/sections/about_section.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

void main() {
  testWidgets('shows the real version and the manual check → up to date', (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.2.3')),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker()..throwsNull = false),
    ]);
    addTearDown(c.dispose);

    await pumpLocalized(tester, const AboutSection(), container: c);
    await tester.pumpAndSettle();
    expect(find.text(_l10n.settingsAboutVersion('1.2.3')), findsOneWidget);
    expect(find.text(_l10n.settingsAboutCheckForUpdates), findsOneWidget);
  });

  testWidgets('toggle flips autoCheckUpdates', (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.0.0')),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker()),
    ]);
    addTearDown(c.dispose);
    await pumpLocalized(tester, const AboutSection(), container: c);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).autoCheckUpdates, true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).autoCheckUpdates, false);
  });

  // A pending download used to REPLACE the manual-check row, which locked the
  // user out of ever finding a newer release: reported from the device as
  // "I can't install it because I get the ready card and not the check one".
  testWidgets('a ready download does not hide the manual check', (tester) async {
    final installer = FakeAppInstaller(version: '1.6.0', nextDownloadId: 5)
      ..status = const DownloadProgress(DownloadStage.done, received: 10, total: 10);
    final store = InMemorySettingsStore();
    await store.write({'pendingUpdateDownloadId': 5, 'pendingUpdateVersion': '1.7.0'});
    final svc = await SettingsService.load(store);
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(installer),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker()),
    ]);
    addTearDown(c.dispose);

    await pumpLocalized(tester, const AboutSection(), container: c);
    await tester.pumpAndSettle();

    expect(find.text(_l10n.settingsAboutReady), findsOneWidget);
    expect(find.text(_l10n.settingsAboutCheckForUpdates), findsOneWidget);
  });
}
