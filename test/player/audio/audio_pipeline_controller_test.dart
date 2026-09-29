import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/audio/audio_pipeline.dart';
import 'package:kivo_player/player/audio/audio_pipeline_controller.dart';
import 'package:kivo_player/player/audio/equalizer.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';

import '../../fakes/fakes.dart';

class _H {
  _H(this.c, this.engine);
  final ProviderContainer c;
  final FakePlaybackEngine engine;
  AudioPipelineController get ctl => c.read(audioPipelineProvider);

  Future<void> set(KivoSettings Function(KivoSettings) f) async {
    await c.read(settingsProvider.notifier).set(f(c.read(settingsProvider)));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  /// A track change the pipeline hears about through the engine stream.
  Future<void> playTrack(String codec, int channels) async {
    engine.audioSourceValue = (codec: codec, channels: channels);
    engine.emitCurrentAudio(null);
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

Future<_H> _harness({KivoSettings Function(KivoSettings)? tweak}) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  if (tweak != null) await svc.update(tweak(svc.current));
  final engine = FakePlaybackEngine();
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    playbackEngineProvider.overrideWithValue(engine),
  ]);
  addTearDown(c.dispose);
  c.read(audioPipelineProvider);
  return _H(c, engine);
}

void main() {
  test('the first apply writes every option once; an identical one writes none',
      () async {
    final h = await _harness();
    await h.ctl.apply();
    expect(h.engine.audioFilters, ['']);
    expect(h.engine.audioWrites, ['gain=0.0', 'downmix=false|', 'drc=0.0']);

    await h.ctl.apply();
    expect(h.engine.audioFilters, hasLength(1));
    expect(h.engine.audioWrites, hasLength(3));
  });

  test('the equalizer preamp reaches mpv as a gain, not as a filter', () async {
    final h = await _harness();
    await h.ctl.apply();
    await h.ctl.apply(
        equalizer:
            EqualizerSettings.flat(enabled: true).copyWith(preampDb: 4));
    expect(h.engine.audioFilters, ['']);
    expect(h.engine.audioWrites.last, 'gain=4.0');
  });

  group('Realzar voces', () {
    test('turning it on downmixes to stereo with the centre raised', () async {
      final h = await _harness();
      await h.ctl.apply();
      await h.playTrack('eac3', 6);
      await h.set((s) => s.copyWith(voiceBoost: true));

      expect(h.engine.audioWrites.last,
          'downmix=true|center_mix_level=1.41,surround_mix_level=0.5');
      expect(h.engine.audioFilters.last, '',
          reason: 'a 5.1 track needs no voice EQ');
    });

    test('a stereo track gets the voice curve instead', () async {
      final h = await _harness(tweak: (s) => s.copyWith(voiceBoost: true));
      await h.ctl.apply();
      await h.playTrack('aac', 2);
      expect(h.engine.audioFilters.last, mpvEqualizerFilter(voiceClarityCurve));
    });

    test('switching 5.1 → stereo changes the EQ but never reloads the downmix',
        () async {
      final h = await _harness(tweak: (s) => s.copyWith(voiceBoost: true));
      await h.playTrack('eac3', 6);
      final downmixes =
          h.engine.audioWrites.where((w) => w.startsWith('downmix')).length;
      await h.playTrack('aac', 2);
      expect(
          h.engine.audioWrites.where((w) => w.startsWith('downmix')).length,
          downmixes);
      expect(h.engine.audioFilters.last, isNot(''));
    });
  });

  group('Modo noche', () {
    test('on a Dolby track the decoder is re-created to hear it', () async {
      final h = await _harness();
      await h.playTrack('ac3', 6);
      await h.set((s) => s.copyWith(nightMode: true));
      expect(h.engine.audioWrites.last, 'drc=2.0');
      expect(h.engine.audioDecoderReloads, 1);
    });

    test('on any other codec the value is set but nothing is reloaded',
        () async {
      final h = await _harness();
      await h.playTrack('aac', 2);
      await h.set((s) => s.copyWith(nightMode: true));
      expect(h.engine.audioWrites.last, 'drc=2.0');
      expect(h.engine.audioDecoderReloads, 0);
    });

    test('the level change is heard too', () async {
      final h = await _harness(tweak: (s) => s.copyWith(nightMode: true));
      await h.playTrack('eac3', 6);
      await h.set((s) => s.copyWith(nightModeLevel: 'strong'));
      expect(h.engine.audioWrites.last, 'drc=4.0');
    });

    test('the first write ever never reloads (no decoder saw the old value)',
        () async {
      final h = await _harness(tweak: (s) => s.copyWith(nightMode: true));
      h.engine.audioSourceValue = (codec: 'ac3', channels: 6);
      await h.ctl.onOpen();
      expect(h.engine.audioDecoderReloads, 0);
    });
  });

  test('an open forgets the previous track and reads the new one directly',
      () async {
    final h = await _harness(tweak: (s) => s.copyWith(voiceBoost: true));
    await h.playTrack('eac3', 6);
    expect(h.c.read(currentAudioSourceProvider)?.codec, 'eac3');

    h.engine.audioSourceValue = (codec: 'aac', channels: 2);
    await h.ctl.onOpen(); // no track event: the list arrived before the open
    expect(h.c.read(currentAudioSourceProvider)?.codec, 'aac');
    expect(h.engine.audioFilters.last, isNot(''));
  });

  test('a write that failed is retried on the next apply', () async {
    final h = await _harness();
    h.engine.audioFilterError = StateError('mpv said no');
    await h.ctl.apply();
    h.engine.audioFilterError = null;
    await h.ctl.apply();
    expect(h.engine.audioFilters, ['']);
  });
}
