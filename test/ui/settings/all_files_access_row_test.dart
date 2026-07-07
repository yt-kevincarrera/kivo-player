import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/all_files_access_provider.dart';
import 'package:kivo_player/ui/settings/sections/advanced_playback_section.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('all-files-access row shows granted state', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(FakeAllFilesAccess(granted: true)),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: AdvancedPlaybackSection()),
    ));
    await tester.pumpAndSettle();

    // The row is the last section — scroll it into view (ListView is lazy).
    await tester.scrollUntilVisible(
        find.text('Acceso a todos los archivos'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Acceso a todos los archivos'), findsOneWidget);
    expect(find.text('Concedido'), findsOneWidget);
  });

  testWidgets('tapping the row requests access when not granted', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final fake = FakeAllFilesAccess(granted: false);
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: AdvancedPlaybackSection()),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
        find.text('Acceso a todos los archivos'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Acceso a todos los archivos'));
    await tester.pumpAndSettle();
    expect(fake.requestCount, 1);
  });
}
