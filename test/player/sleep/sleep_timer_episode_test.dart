import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import '../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer container;

  Future<void> setUpContainer() async {
    engine = FakePlaybackEngine();
    final s = await SettingsService.load(InMemorySettingsStore());
    container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);
    addTearDown(engine.dispose);
    container.listen(sleepTimerProvider, (_, __) {});
    // Streams are broadcast without replay: subscribe (via the providers the
    // notifier listens through) BEFORE emitting.
    container.listen(positionProvider, (_, __) {});
    container.listen(durationProvider, (_, __) {});
  }

  // Two microtask turns: one for the StreamController delivery, one for the
  // StreamProvider's AsyncValue hop.
  Future<void> pumpStreams() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('episode mode tracks remaining = duration - position', () async {
    await setUpContainer();
    container.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 4));
    await pumpStreams();
    final st = container.read(sleepTimerProvider)!;
    expect(st.mode, SleepTimerMode.episode);
    expect(st.remaining, const Duration(minutes: 6));
    expect(st.warning, false);
  });

  test('episode mode enters warning at <=10s from the end and fades', () async {
    await setUpContainer();
    container.read(volumePercentProvider.notifier).state = 100;
    container.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 9, seconds: 52));
    await pumpStreams();
    expect(container.read(sleepTimerProvider)!.warning, true);
    expect(engine.volume, lessThan(100));
  });

  test('episode mode fires at the end of the video (pause + restore + null)', () async {
    await setUpContainer();
    container.read(volumePercentProvider.notifier).state = 100;
    container.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 10));
    await pumpStreams();
    expect(engine.lastPlayingCommand, false);
    expect(engine.volume, 100);
    expect(container.read(sleepTimerProvider), isNull);
  });

  test('opening another video re-applies episode mode to the new video', () async {
    await setUpContainer();
    container.read(volumePercentProvider.notifier).state = 100;
    container.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 9, seconds: 55));
    await pumpStreams();
    expect(container.read(sleepTimerProvider)!.warning, true);

    // New video opens: warning resets, volume restored, mode stays active.
    container.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep2.mkv', displayName: 'ep2.mkv', queue: ['/v/ep2.mkv'], index: 0),
    );
    engine.emitDuration(const Duration(minutes: 20));
    engine.emitPosition(Duration.zero);
    await pumpStreams();
    final st = container.read(sleepTimerProvider)!;
    expect(st.mode, SleepTimerMode.episode);
    expect(st.warning, false);
    expect(engine.volume, 100);
  });

  test('extend in episode mode cancels the timer', () async {
    await setUpContainer();
    container.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 9, seconds: 55));
    await pumpStreams();
    container.read(sleepTimerProvider.notifier).extend();
    expect(container.read(sleepTimerProvider), isNull);
    // Playback untouched by the cancel itself:
    expect(engine.lastPlayingCommand, isNot(false));
  });
}
