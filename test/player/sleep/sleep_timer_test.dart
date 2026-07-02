import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import '../../fakes/fakes.dart';

void main() {
  test('KivoSettings.sleepTimerLastMinutes defaults to 30 and round-trips', () {
    final d = KivoSettings.defaults();
    expect(d.sleepTimerLastMinutes, 30);
    final back = KivoSettings.fromMap(d.copyWith(sleepTimerLastMinutes: 45).toMap());
    expect(back.sleepTimerLastMinutes, 45);
  });

  // Shared harness: a controllable clock + container. `now` is mutated by the
  // test; the notifier's periodic ticker reads it through sleepClockProvider.
  late DateTime now;
  late FakePlaybackEngine engine;
  late ProviderContainer container;

  Future<ProviderContainer> makeContainer() async {
    engine = FakePlaybackEngine();
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      sleepClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(c.dispose);
    addTearDown(engine.dispose);
    // Keep the notifier alive for the whole test.
    c.listen(sleepTimerProvider, (_, __) {});
    return c;
  }

  test('startFixed sets state with original, remaining and no warning', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
      final st = container.read(sleepTimerProvider)!;
      expect(st.mode, SleepTimerMode.fixed);
      expect(st.original, const Duration(minutes: 30));
      expect(st.remaining, const Duration(minutes: 30));
      expect(st.warning, false);
    });
  });

  test('ticker updates remaining and enters warning at <=10s', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
      now = now.add(const Duration(minutes: 29, seconds: 52));
      async.elapse(const Duration(milliseconds: 300));
      final st = container.read(sleepTimerProvider)!;
      expect(st.warning, true);
      expect(st.remaining.inSeconds, lessThanOrEqualTo(10));
    });
  });

  test('fade lowers player volume during warning and restores it on fire', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(volumePercentProvider.notifier).state = 100;
      container.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
      // Jump into the middle of the warning window: 5s remaining → factor 0.5.
      now = now.add(const Duration(minutes: 29, seconds: 55));
      async.elapse(const Duration(milliseconds: 300));
      expect(engine.volume, lessThan(100));
      // Cross endsAt → fire.
      now = now.add(const Duration(seconds: 6));
      async.elapse(const Duration(milliseconds: 300));
      expect(engine.lastPlayingCommand, false); // paused
      expect(engine.volume, 100); // restored to the user's mapped level
      expect(container.read(sleepTimerProvider), isNull); // one-shot
    });
  });

  test('extend ADDS the original duration to the remaining time and restores volume', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(volumePercentProvider.notifier).state = 100;
      final n = container.read(sleepTimerProvider.notifier);
      n.startFixed(const Duration(minutes: 30));
      now = now.add(const Duration(minutes: 29, seconds: 55));
      async.elapse(const Duration(milliseconds: 300));
      final before = container.read(sleepTimerProvider)!;
      expect(before.warning, true);
      n.extend();
      final st = container.read(sleepTimerProvider)!;
      expect(st.warning, false);
      // Additive: ~5s were left, +30 min → just over 30 min, NOT a restart to 30.
      expect(st.remaining, const Duration(minutes: 30, seconds: 5));
      expect(st.original, const Duration(minutes: 30)); // preset unchanged
      expect(st.cycle, greaterThan(before.cycle)); // new cycle → toast reappears next time
      expect(engine.volume, 100);

      // Extending twice mid-run must never shorten the timer.
      n.extend();
      expect(container.read(sleepTimerProvider)!.remaining,
          const Duration(minutes: 60, seconds: 5));
    });
  });

  test('cancel clears state and restores volume', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(volumePercentProvider.notifier).state = 100;
      final n = container.read(sleepTimerProvider.notifier);
      n.startFixed(const Duration(minutes: 30));
      now = now.add(const Duration(minutes: 29, seconds: 55));
      async.elapse(const Duration(milliseconds: 300));
      n.cancel();
      expect(container.read(sleepTimerProvider), isNull);
      expect(engine.volume, 100);
      // No pause on cancel:
      expect(engine.lastPlayingCommand, isNot(false));
    });
  });

  test('manual volume change during fade cancels the fade but not the timer', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(volumePercentProvider.notifier).state = 100;
      container.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
      now = now.add(const Duration(minutes: 29, seconds: 55));
      async.elapse(const Duration(milliseconds: 300));
      expect(engine.volume, lessThan(100));
      // User adjusts volume mid-fade (gesture already applied its own engine volume).
      container.read(volumePercentProvider.notifier).state = 60;
      engine.volume = 77; // whatever the gesture set on the engine
      async.elapse(const Duration(milliseconds: 600));
      expect(engine.volume, 77); // fade no longer overrides
      expect(container.read(sleepTimerProvider), isNotNull); // timer still running
      expect(container.read(sleepTimerProvider)!.warning, true);
    });
  });
}
