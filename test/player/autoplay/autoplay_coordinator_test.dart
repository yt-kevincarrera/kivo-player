import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/autoplay/autoplay_coordinator.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';
import '../../fakes/fakes.dart';

const _twoItem = VideoSession(
  playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv',
  queue: ['/v/ep1.mkv', '/v/ep2.mkv'], queueNames: ['ep1.mkv', 'ep2.mkv'],
  queueIds: ['1', '2'], index: 0);

Future<(ProviderContainer, FakePlaybackEngine)> _setup(WidgetTester t,
    {bool minimized = true, bool autoplay = true}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  await s.update(s.current.copyWith(autoplayNext: autoplay));
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    resumeServiceProvider.overrideWithValue(FakeResumeService()),
    subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
    playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(_twoItem);
  c.read(playerMinimizedProvider.notifier).state = minimized;
  c.read(autoplayCoordinatorProvider); // instantiate + start listening
  return (c, engine);
}

Future<void> _pump(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('minimized + autoplay on → completing advances to the next video', (t) async {
    final (c, engine) = await _setup(t);
    engine.emitCompleted(true);
    await t.pump();
    // Resolve applyDefaultTracks' stream .first so no 2s timer lingers.
    // The audio and subtitle .first subscriptions are set up sequentially
    // (subtitle only after the audio await resolves), so each emit needs its
    // own pump to let the next subscription attach before it fires.
    engine.emitAudioTracks(const []);
    await t.pump();
    engine.emitSubtitleTracks(const []);
    await _pump(t);
    expect(engine.openedPath, '/v/ep2.mkv');
    expect(c.read(currentVideoProvider)!.index, 1);
    expect(engine.lastPlayingCommand, true);
  });

  testWidgets('NOT minimized → completing does not advance (PlayerScreen owns it)', (t) async {
    final (c, engine) = await _setup(t, minimized: false);
    engine.emitCompleted(true);
    await _pump(t);
    expect(engine.openedPath, isNull);
    expect(c.read(currentVideoProvider)!.index, 0);
  });

  testWidgets('autoplay off → completing does not advance', (t) async {
    final (c, engine) = await _setup(t, autoplay: false);
    engine.emitCompleted(true);
    await _pump(t);
    expect(engine.openedPath, isNull);
  });

  testWidgets('last video (no next) → completing does not advance', (t) async {
    final (c, engine) = await _setup(t);
    c.read(currentVideoProvider.notifier).advanceTo(
      c.read(currentVideoProvider.notifier).sessionAt(1)!); // move to last
    engine.openedPath = null; // ignore the advanceTo bookkeeping
    engine.emitCompleted(true);
    await _pump(t);
    expect(engine.openedPath, isNull);
  });
}
