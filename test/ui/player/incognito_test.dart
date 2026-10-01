import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';
import 'video_ready_test.dart' show NoopControls;

Future<(InMemoryPlayedStore, InMemoryResumeStore, FakePlaybackEngine)> _play(
    WidgetTester tester, {required bool incognito}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  await s.update(s.current.copyWith(gestureMapShown: true, incognito: incognito));
  final played = InMemoryPlayedStore();
  final resume = InMemoryResumeStore();
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    deviceControlsProvider.overrideWithValue(NoopControls()),
    resumeServiceProvider.overrideWithValue(ResumeService(resume)),
    playedStoreProvider.overrideWithValue(played),
    bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
    frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
    subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    pipControllerProvider.overrideWithValue(FakePipController()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(const VideoSession(
      playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));
  await pumpLocalized(tester, const PlayerScreen(), container: c);
  await tester.pump();
  // Ten minutes in, then the periodic save (every 4 s) fires.
  engine.emitDuration(const Duration(minutes: 30));
  engine.emitPosition(const Duration(minutes: 10));
  await tester.pump(const Duration(seconds: 5));
  return (played, resume, engine);
}

void main() {
  testWidgets('normally, watching marks the video and saves where you are',
      (tester) async {
    final (played, resume, _) = await _play(tester, incognito: false);
    expect(played.keys(), contains('ep1.mkv'));
    expect(resume.entries().map((e) => e.key), contains('ep1.mkv'));
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('incognito: no "played" mark and no resume position',
      (tester) async {
    final (played, resume, _) = await _play(tester, incognito: true);
    expect(played.keys(), isEmpty);
    expect(resume.entries(), isEmpty);
    await tester.pump(const Duration(seconds: 6));
  });

  test('incognito round-trips and defaults off', () {
    expect(KivoSettings.defaults().incognito, isFalse);
    final back = KivoSettings.fromMap(
        KivoSettings.defaults().copyWith(incognito: true).toMap());
    expect(back.incognito, isTrue);
  });
}
