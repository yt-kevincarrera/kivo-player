import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/ui/player/more/more_menu.dart';
import 'package:kivo_player/ui/player/tracks/track_sync_hud.dart';
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
      trackPrefsStoreProvider.overrideWithValue(InMemoryTrackPrefsStore()),
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
    expect(find.text('Sincronizar audio y subtítulos'), findsOneWidget);

    // The menu has grown past what fits on screen without scrolling (the
    // equalizer entry now follows this one) — scroll it into view the same
    // way a real user would before tapping it.
    await tester.dragUntilVisible(
      find.text('Sincronizar audio y subtítulos'),
      find.byType(Scrollable),
      const Offset(0, -80),
    );
    await tester.tap(find.text('Sincronizar audio y subtítulos'));
    await tester.pumpAndSettle();

    // A subtitle is showing, so the capsule opens on that side.
    expect(c.read(syncHudProvider), SyncTarget.subtitles);
    // The sheet is gone — it would otherwise cover the subtitle being adjusted.
    expect(find.text('Bucle A-B'), findsNothing);
  });

  // With no subtitle showing there is still audio to adjust, so the entry
  // stays usable — it just opens on the side that works. Hiding or disabling
  // it here would repeat the "no option anywhere" report the subtitle-only
  // version earned.
  testWidgets('with no subtitle active the entry opens the capsule on audio',
      (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
      trackPrefsStoreProvider.overrideWithValue(InMemoryTrackPrefsStore()),
    ]);
    addTearDown(c.dispose);

    await _pumpMenu(tester, c);
    expect(find.text('Sincronizar audio y subtítulos'), findsOneWidget);

    // The menu has grown past what fits on screen without scrolling (the
    // equalizer entry now follows this one) — scroll it into view the same
    // way a real user would before tapping it.
    await tester.dragUntilVisible(
      find.text('Sincronizar audio y subtítulos'),
      find.byType(Scrollable),
      const Offset(0, -80),
    );
    await tester.tap(find.text('Sincronizar audio y subtítulos'));
    await tester.pumpAndSettle();

    expect(c.read(syncHudProvider), SyncTarget.audio);
    expect(find.text('Bucle A-B'), findsNothing);
  });

  testWidgets('the entry follows the subtitle track going active',
      (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final engine = FakePlaybackEngine();
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      playbackEngineProvider.overrideWithValue(engine),
      trackPrefsStoreProvider.overrideWithValue(InMemoryTrackPrefsStore()),
    ]);
    addTearDown(c.dispose);

    await _pumpMenu(tester, c);
    engine.emitCurrentSubtitle(const MediaTrack(id: 'sub1'));
    await tester.pumpAndSettle();

    // The menu has grown past what fits on screen without scrolling (the
    // equalizer entry now follows this one) — scroll it into view the same
    // way a real user would before tapping it.
    await tester.dragUntilVisible(
      find.text('Sincronizar audio y subtítulos'),
      find.byType(Scrollable),
      const Offset(0, -80),
    );
    await tester.tap(find.text('Sincronizar audio y subtítulos'));
    await tester.pumpAndSettle();
    expect(c.read(syncHudProvider), SyncTarget.subtitles);
  });
}
