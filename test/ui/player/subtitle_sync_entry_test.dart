import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import 'package:kivo_player/ui/player/more/more_menu.dart';
import 'package:kivo_player/ui/player/tracks/subtitle_sync_hud.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('the more menu opens the sync HUD and closes itself', (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
      subtitlePrefsStoreProvider.overrideWithValue(InMemorySubtitlePrefsStore()),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Consumer(builder: (ctx, ref, _) {
          return Scaffold(body: Builder(builder: (b) {
            return TextButton(
              onPressed: () => showMoreMenu(b, ref),
              child: const Text('open'),
            );
          }));
        }),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Sincronizar subtítulos'), findsOneWidget);

    await tester.tap(find.text('Sincronizar subtítulos'));
    await tester.pumpAndSettle();

    expect(c.read(subtitleSyncVisibleProvider), true);
    // The sheet is gone — it would otherwise cover the subtitle being adjusted.
    expect(find.text('Bucle A-B'), findsNothing);
  });
}
