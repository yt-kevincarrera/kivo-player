import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import '../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;
  Future<void> setUp_() async {
    engine = FakePlaybackEngine();
    final s = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose); addTearDown(engine.dispose);
    c.listen(sleepTimerProvider, (_, __) {});
  }

  test('startEpisodes sets mode and count; sleepStopsHere true only at last', () async {
    await setUp_();
    final n = c.read(sleepTimerProvider.notifier);
    n.startEpisodes(3);
    expect(c.read(sleepTimerProvider)!.mode, SleepTimerMode.episodes);
    expect(c.read(sleepTimerProvider)!.episodesLeft, 3);
    expect(sleepStopsHere(c.read(sleepTimerProvider)), false);
    n.onAutoplayAdvance(); // 3 -> 2
    expect(c.read(sleepTimerProvider)!.episodesLeft, 2);
    n.onAutoplayAdvance(); // 2 -> 1
    expect(sleepStopsHere(c.read(sleepTimerProvider)), true); // last one stops
  });

  test('episode mode always stops here', () async {
    await setUp_();
    c.read(sleepTimerProvider.notifier).startEpisode();
    expect(sleepStopsHere(c.read(sleepTimerProvider)), true);
  });

  test('sleepStopsHere is false with no timer or fixed mode', () async {
    await setUp_();
    expect(sleepStopsHere(null), false);
    c.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
    expect(sleepStopsHere(c.read(sleepTimerProvider)), false);
    c.read(sleepTimerProvider.notifier).cancel();
  });
}
