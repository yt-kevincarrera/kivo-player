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
