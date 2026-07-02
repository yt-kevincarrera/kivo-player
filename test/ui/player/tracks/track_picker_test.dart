import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/tracks/track_picker.dart';
import '../../../fakes/fakes.dart';

Future<ProviderContainer> _pumpAndOpenSheet(
  WidgetTester tester, {
  required bool subtitles,
}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(
    const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
  );

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: KivoTheme.dark(),
      home: Scaffold(
        body: Center(
          // Consumer (not a plain Builder) is what gives this callback a
          // real WidgetRef — showSubtitlePicker/showAudioPicker take
          // (BuildContext, WidgetRef), not a raw ProviderContainer.
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () =>
                  subtitles ? showSubtitlePicker(context, ref) : showAudioPicker(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();

  // Open the sheet first so its StreamBuilders are subscribed, then emit —
  // these are broadcast streams (no replay of the last value), matching
  // MediaKitEngine's real track streams, so emitting before the sheet
  // mounts would be lost, same as it would be for any late subscriber.
  await tester.tap(find.text('open'));
  await tester.pump();

  if (subtitles) {
    engine.emitSubtitleTracks(const [MediaTrack(id: 'sub-en', title: 'English', language: 'en')]);
  } else {
    engine.emitAudioTracks(const [MediaTrack(id: 'aud-en', title: 'English', language: 'en')]);
  }
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('subtitle sheet shows the "Mostrar subtítulos" switch plus tracks', (tester) async {
    await _pumpAndOpenSheet(tester, subtitles: true);
    expect(find.text('Mostrar subtítulos'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('audio sheet lists tracks without the subtitles switch', (tester) async {
    await _pumpAndOpenSheet(tester, subtitles: false);
    expect(find.text('Mostrar subtítulos'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('turning the switch off turns subtitles off and persists the choice',
      (tester) async {
    final c = await _pumpAndOpenSheet(tester, subtitles: true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).subtitlesEnabledByDefault, false);
  });

  testWidgets('the Estilo tab shows the live preview and hides the track list',
      (tester) async {
    await _pumpAndOpenSheet(tester, subtitles: true);
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.text('Estilo'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsNothing);
    expect(find.text('Estamos cerca de encontrarlo.'), findsOneWidget);
  });
}
