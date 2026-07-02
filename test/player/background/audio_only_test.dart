import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/background/audio_only.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import '../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;

  Future<void> setUpContainer() async {
    engine = FakePlaybackEngine();
    final s = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    addTearDown(engine.dispose);
    c.listen(audioOnlyProvider, (_, __) {});
  }

  test('toggle turns the video track off and back on', () async {
    await setUpContainer();
    final n = c.read(audioOnlyProvider.notifier);
    expect(c.read(audioOnlyProvider), false);
    expect(engine.videoTrackEnabled, true);
    n.toggle();
    expect(c.read(audioOnlyProvider), true);
    expect(engine.videoTrackEnabled, false);
    n.toggle();
    expect(c.read(audioOnlyProvider), false);
    expect(engine.videoTrackEnabled, true);
  });

  test('changing video resets audio-only and re-enables the video track', () async {
    await setUpContainer();
    c.read(audioOnlyProvider.notifier).toggle();
    expect(engine.videoTrackEnabled, false);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep2.mkv', displayName: 'ep2.mkv', queue: ['/v/ep2.mkv'], index: 0),
    );
    await Future<void>.delayed(Duration.zero);
    expect(c.read(audioOnlyProvider), false);
    expect(engine.videoTrackEnabled, true);
  });

  test('disable is a no-op when already off, otherwise restores video', () async {
    await setUpContainer();
    final n = c.read(audioOnlyProvider.notifier);
    n.disable(); // no-op
    expect(engine.videoTrackEnabled, true);
    n.toggle();
    n.disable();
    expect(c.read(audioOnlyProvider), false);
    expect(engine.videoTrackEnabled, true);
  });
}
