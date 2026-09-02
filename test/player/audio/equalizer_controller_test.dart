import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/audio/equalizer.dart';
import 'package:kivo_player/player/audio/equalizer_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _container(FakePlaybackEngine engine) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
  ]);
  return c;
}

void main() {
  test('ten rapid setBand calls reach mpv exactly once, with the final graph', () async {
    final engine = FakePlaybackEngine();
    final c = await _container(engine);
    addTearDown(c.dispose);

    fakeAsync((async) {
      final n = c.read(equalizerProvider.notifier);
      n.setEnabled(true);
      for (var i = 0; i < 10; i++) {
        n.setBand(i, i.toDouble());
      }
      // The UI already shows every step before mpv has heard anything.
      final state = c.read(equalizerProvider);
      expect(state.gainsDb, [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]);
      expect(engine.audioFilters, isEmpty);

      async.elapse(const Duration(milliseconds: 200));

      expect(engine.audioFilters, [mpvAudioFilter(state)]);
    });
  });

  test('the settled curve is persisted into settings', () async {
    final engine = FakePlaybackEngine();
    final c = await _container(engine);
    addTearDown(c.dispose);

    fakeAsync((async) {
      c.read(equalizerProvider.notifier).setEnabled(true);
      c.read(equalizerProvider.notifier).setBand(0, 4.0);
      async.elapse(const Duration(milliseconds: 200));

      expect(c.read(settingsProvider).equalizer.enabled, true);
      expect(c.read(settingsProvider).equalizer.gainsDb[0], 4.0);
    });
  });

  test('applyPreset sets the curve immediately and debounces the engine call', () async {
    final engine = FakePlaybackEngine();
    final c = await _container(engine);
    addTearDown(c.dispose);

    fakeAsync((async) {
      c.read(equalizerProvider.notifier).setEnabled(true);
      c.read(equalizerProvider.notifier).applyPreset('Graves');
      expect(c.read(equalizerProvider).gainsDb, equalizerPresetCurves['Graves']);
      expect(engine.audioFilters, isEmpty);

      async.elapse(const Duration(milliseconds: 200));
      expect(engine.audioFilters, hasLength(1));
    });
  });

  test('setPreamp clamps to range', () async {
    final engine = FakePlaybackEngine();
    final c = await _container(engine);
    addTearDown(c.dispose);
    c.read(equalizerProvider.notifier).setPreamp(99);
    expect(c.read(equalizerProvider).preampDb, equalizerMaxDb);
  });

  test('resetCurve goes back to flat/zero preamp without touching enabled', () async {
    final engine = FakePlaybackEngine();
    final c = await _container(engine);
    addTearDown(c.dispose);

    fakeAsync((async) {
      final n = c.read(equalizerProvider.notifier);
      n.setEnabled(true);
      n.applyPreset('Agudos');
      n.setPreamp(5);
      async.elapse(const Duration(milliseconds: 200));

      n.resetCurve();
      async.elapse(const Duration(milliseconds: 200));

      final state = c.read(equalizerProvider);
      expect(state.enabled, true);
      expect(state.preampDb, 0);
      expect(state.gainsDb, List.filled(10, 0.0));
    });
  });

  test('flush applies a pending change immediately instead of losing it', () async {
    final engine = FakePlaybackEngine();
    final c = await _container(engine);
    addTearDown(c.dispose);

    c.read(equalizerProvider.notifier).setEnabled(true);
    c.read(equalizerProvider.notifier).setBand(0, 3.0);
    await c.read(equalizerProvider.notifier).flush();

    expect(engine.audioFilters, hasLength(1));
    expect(c.read(settingsProvider).equalizer.gainsDb[0], 3.0);
  });

  test(
      'a drag that lands during the debounced apply\'s awaited engine call is '
      'not lost — the final value wins and the engine is called with it', () async {
    final engine = FakePlaybackEngine();
    final c = await _container(engine);
    addTearDown(c.dispose);

    fakeAsync((async) {
      final n = c.read(equalizerProvider.notifier);
      n.setEnabled(true);
      async.elapse(const Duration(milliseconds: 200));
      expect(engine.audioFilters, hasLength(1)); // setEnabled's own apply landed

      // Hold the next engine round trip open so a second drag can land
      // while it's still in flight.
      engine.audioFilterGate = Completer<void>();
      n.setBand(0, 4.0); // first value ("A")
      async.elapse(const Duration(milliseconds: 200)); // debounce fires, _apply awaits the gate
      expect(engine.audioFilters, hasLength(1)); // A hasn't reached the engine yet — still blocked on the gate

      n.setBand(0, 9.0); // second value ("B") lands mid-flight
      expect(c.read(equalizerProvider).gainsDb[0], 9.0); // UI reflects B immediately

      // Let A's engine call (and settings write) land.
      engine.audioFilterGate!.complete();
      engine.audioFilterGate = null;
      async.flushMicrotasks();

      // The settings write for A must not have reverted the slider to A.
      expect(c.read(equalizerProvider).gainsDb[0], 9.0);
      expect(engine.audioFilters, hasLength(2)); // A did reach the engine...
      expect(engine.audioFilters.last, contains('g=4.0'));

      // B's own debounce (scheduled when it landed) now fires.
      async.elapse(const Duration(milliseconds: 200));

      expect(c.read(equalizerProvider).gainsDb[0], 9.0);
      expect(engine.audioFilters, hasLength(3)); // ...and so did B, last
      expect(engine.audioFilters.last, contains('g=9.0'));
      expect(c.read(settingsProvider).equalizer.gainsDb[0], 9.0);
    });
  });

  test('an external settings change while idle is adopted (e.g. Ajustes → Restablecer valores)', () async {
    final engine = FakePlaybackEngine();
    final c = await _container(engine);
    addTearDown(c.dispose);

    // Establish the watch dependency first.
    c.read(equalizerProvider);

    final reset = EqualizerSettings(
      enabled: true,
      preampDb: 2.0,
      gainsDb: List.filled(equalizerBandsHz.length, 3.0),
    );
    await c.read(settingsProvider.notifier).set(
          c.read(settingsProvider).copyWith(equalizer: reset),
        );

    expect(c.read(equalizerProvider), reset);
  });

  test('is seeded from whatever equalizer settings already exist', () async {
    final engine = FakePlaybackEngine();
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(
      equalizer: EqualizerSettings(
        enabled: true,
        preampDb: 1.5,
        gainsDb: equalizerPresetCurves['Voz']!,
      ),
    ));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);

    final state = c.read(equalizerProvider);
    expect(state.enabled, true);
    expect(state.preampDb, 1.5);
    expect(state.gainsDb, equalizerPresetCurves['Voz']);
  });
}
