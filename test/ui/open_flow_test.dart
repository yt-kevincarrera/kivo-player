import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import '../fakes/fakes.dart';

void main() {
  testWidgets('opening a video with saved resume seeks engine to that position',
      (tester) async {
    final engine = FakePlaybackEngine();
    final resumeStore = InMemoryResumeStore();
    // Resume is keyed by the stable basename (VideoSession.resumeKey), not the
    // full path — Android's file picker copies into a per-pick cache dir.
    await resumeStore.put('ep1.mkv', 120); // 2 min saved
    final settingsService = await SettingsService.load(InMemorySettingsStore());

    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(settingsService),
      playbackEngineProvider.overrideWithValue(engine),
      resumeServiceProvider.overrideWithValue(ResumeService(resumeStore)),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
    ]);
    addTearDown(container.dispose);

    container.read(currentVideoProvider.notifier).open(
          const VideoSession(playbackPath: '/movies/ep1.mkv', displayName: 'ep1.mkv', queue: ['/movies/ep1.mkv'], index: 0),
        );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pump();

    expect(engine.openedPath, '/movies/ep1.mkv');
    expect(engine.openedAt, const Duration(seconds: 120));
  });
}
