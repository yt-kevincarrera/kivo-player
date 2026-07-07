import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/all_files_access_provider.dart';
import 'package:kivo_player/ui/home/widgets/video_options_sheet.dart';
import '../../fakes/fakes.dart';

Widget _host(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(body: Consumer(builder: (context, ref, _) {
          return ElevatedButton(
            onPressed: () => maybeOfferAllFilesAccess(context, ref),
            child: const Text('go'),
          );
        })),
      ),
    );

void main() {
  testWidgets('offers once when not granted and not yet offered', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final fake = FakeAllFilesAccess(granted: false);
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_host(c));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Offer dialog shows; the flag is now set.
    expect(find.text('Dar acceso'), findsOneWidget);
    expect(c.read(settingsProvider).offeredAllFilesAccess, true);

    // Accept → requests access.
    await tester.tap(find.text('Dar acceso'));
    await tester.pumpAndSettle();
    expect(fake.requestCount, 1);
  });

  testWidgets('does not offer when already offered', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(offeredAllFilesAccess: true));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(FakeAllFilesAccess(granted: false)),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_host(c));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Dar acceso'), findsNothing);
  });

  testWidgets('does not offer when already granted', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(FakeAllFilesAccess(granted: true)),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_host(c));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Dar acceso'), findsNothing);
  });
}
