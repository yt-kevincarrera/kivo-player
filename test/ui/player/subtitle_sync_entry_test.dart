import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import 'package:kivo_player/ui/player/more/more_menu.dart';
import 'package:kivo_player/ui/player/tracks/subtitle_sync_hud.dart';
import '../../fakes/fakes.dart';

Future<void> _pumpMenu(WidgetTester tester, ProviderContainer c) async {
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
}

void main() {
  testWidgets('the more menu opens the sync HUD and closes itself', (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final engine = FakePlaybackEngine()
      ..currentSubtitleTrackValue = const MediaTrack(id: 'sub1', language: 'es');
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      playbackEngineProvider.overrideWithValue(engine),
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

  // Spec §2: with no subtitle showing, sub-delay changes nothing on screen, so
  // the entry would be a control that visibly does nothing. Same gate the
  // track picker already applies to its own sync row.
  testWidgets('the sync entry is absent with no subtitle track active',
      (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
      subtitlePrefsStoreProvider.overrideWithValue(InMemorySubtitlePrefsStore()),
    ]);
    addTearDown(c.dispose);

    await _pumpMenu(tester, c);
    expect(find.text('Bucle A-B'), findsOneWidget);
    expect(find.text('Sincronizar subtítulos'), findsNothing);
  });

  testWidgets('the sync entry appears when a subtitle track goes active',
      (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final engine = FakePlaybackEngine();
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      playbackEngineProvider.overrideWithValue(engine),
      subtitlePrefsStoreProvider.overrideWithValue(InMemorySubtitlePrefsStore()),
    ]);
    addTearDown(c.dispose);

    await _pumpMenu(tester, c);
    expect(find.text('Sincronizar subtítulos'), findsNothing);

    engine.emitCurrentSubtitle(const MediaTrack(id: 'sub1'));
    await tester.pumpAndSettle();
    expect(find.text('Sincronizar subtítulos'), findsOneWidget);
  });
}
