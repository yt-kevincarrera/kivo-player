import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/tracks/track_picker.dart';
import '../../../fakes/fakes.dart';

void main() {
  testWidgets('subtitle picker shows tracks from the snapshot without any stream emission', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    // Seed only the snapshot getters — never call emitSubtitleTracks/
    // emitCurrentSubtitle. This proves the picker reads currentSubtitleTracks/
    // currentSubtitleTrack via initialData rather than waiting on a stream
    // emission that (per the real broadcast streams) may never arrive after
    // the panel opens late.
    engine.subtitleTracksValue = const [
      MediaTrack(id: 's', title: 'Español', language: 'spa'),
      MediaTrack(id: 'e', title: 'English', language: 'eng'),
    ];
    engine.currentSubtitleTrackValue = const MediaTrack(id: 's', title: 'Español', language: 'spa');
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/x.mkv', displayName: 'x.mkv', queue: ['/v/x.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            // Consumer (not a plain Builder) gives this callback a real
            // WidgetRef — showSubtitlePicker takes (BuildContext, WidgetRef).
            child: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showSubtitlePicker(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    // Deliberately pumpAndSettle with no engine.emitSubtitleTracks/
    // emitCurrentSubtitle call anywhere above — if the StreamBuilders were
    // still relying solely on stream emissions, this would time out with
    // an empty list (the bug this task fixes).
    await tester.pumpAndSettle();

    expect(find.text('Español'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });
}
