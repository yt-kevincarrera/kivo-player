import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/all_files_access_provider.dart';
import 'package:kivo_player/ui/settings/sections/advanced_playback_section.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

void main() {
  testWidgets('all-files-access row shows granted state', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(FakeAllFilesAccess(granted: true)),
    ]);
    addTearDown(c.dispose);

    await pumpLocalized(tester, const AdvancedPlaybackSection(), container: c);
    await tester.pumpAndSettle();

    // The row is the last section — scroll it into view (ListView is lazy).
    await tester.scrollUntilVisible(
        find.text(_l10n.settingsAdvancedAllFilesAccess), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text(_l10n.settingsAdvancedAllFilesAccess), findsOneWidget);
    expect(find.text(_l10n.settingsAdvancedAllFilesAccessGranted), findsOneWidget);
  });

  testWidgets('tapping the row requests access when not granted', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final fake = FakeAllFilesAccess(granted: false);
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);

    await pumpLocalized(tester, const AdvancedPlaybackSection(), container: c);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
        find.text(_l10n.settingsAdvancedAllFilesAccess), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text(_l10n.settingsAdvancedAllFilesAccess));
    await tester.pumpAndSettle();
    expect(fake.requestCount, 1);
  });
}
