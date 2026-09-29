import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/audio/audio_pipeline.dart';
import 'package:kivo_player/player/audio/equalizer.dart';

AudioPipeline _p({
  EqualizerSettings? eq,
  bool night = false,
  EnhancementLevel nightLevel = EnhancementLevel.medium,
  bool voice = false,
  EnhancementLevel voiceLevel = EnhancementLevel.medium,
  AudioSource? source,
}) =>
    buildAudioPipeline(
      equalizer: eq ?? EqualizerSettings.flat(),
      nightMode: night,
      nightLevel: nightLevel,
      voiceBoost: voice,
      voiceLevel: voiceLevel,
      source: source,
    );

const _stereo = AudioSource(codec: 'aac', channels: 2);
const _dolby51 = AudioSource(codec: 'eac3', channels: 6);

void main() {
  test('everything off writes mpv back to its defaults', () {
    expect(
        _p(),
        const AudioPipeline(
            af: '', gainDb: 0, forceStereo: false, swresample: '', drc: 0));
  });

  test('the equalizer preamp is a gain, never part of the filter graph', () {
    final p =
        _p(eq: EqualizerSettings.flat(enabled: true).copyWith(preampDb: 3));
    expect(p.af, '');
    expect(p.gainDb, 3);
  });

  test('a disabled equalizer contributes neither bands nor preamp', () {
    final p = _p(
        eq: EqualizerSettings.flat(enabled: false)
            .withBand(0, 6)
            .copyWith(preampDb: 4));
    expect(p.af, '');
    expect(p.gainDb, 0);
  });

  group('Modo noche', () {
    test('maps each level to the Dolby DRC scale', () {
      expect(_p(night: true, nightLevel: EnhancementLevel.soft).drc, 1.0);
      expect(_p(night: true, nightLevel: EnhancementLevel.medium).drc, 2.0);
      expect(_p(night: true, nightLevel: EnhancementLevel.strong).drc, 4.0);
    });

    test('touches nothing else', () {
      final p = _p(night: true, source: _dolby51);
      expect(p.af, '');
      expect(p.forceStereo, isFalse);
      expect(p.swresample, '');
    });
  });

  group('Realzar voces', () {
    test('a 5.1 source is downmixed with the centre raised, EQ untouched', () {
      final p = _p(voice: true, source: _dolby51);
      expect(p.forceStereo, isTrue);
      expect(p.swresample, 'center_mix_level=1.41,surround_mix_level=0.5');
      expect(p.af, '');
      expect(p.gainDb, 0);
    });

    test('the level picks the centre mix', () {
      expect(
          _p(voice: true, voiceLevel: EnhancementLevel.soft, source: _dolby51)
              .swresample,
          startsWith('center_mix_level=1.0,'));
      expect(
          _p(voice: true, voiceLevel: EnhancementLevel.strong, source: _dolby51)
              .swresample,
          startsWith('center_mix_level=2.0,'));
    });

    test('a stereo source gets the voice curve and a clipping guard', () {
      final p = _p(voice: true, source: _stereo);
      expect(p.af, mpvEqualizerFilter(voiceClarityCurve));
      expect(p.gainDb, voiceClarityCompensationDb);
    });

    test('an unknown source is treated as stereo until it is known', () {
      expect(_p(voice: true).af, isNotEmpty);
    });

    test('stereo and downmix values are written for any source', () {
      // So a track switch between stereo and 5.1 never reloads the chain.
      expect(_p(voice: true, source: _stereo).forceStereo, isTrue);
      expect(_p(voice: true, source: _stereo).swresample, isNotEmpty);
    });

    test("the voice curve adds onto the user's EQ and is clamped", () {
      final eq = EqualizerSettings.flat(enabled: true)
          .withBand(5, 11)
          .copyWith(preampDb: 1);
      final p = _p(
          eq: eq,
          voice: true,
          voiceLevel: EnhancementLevel.strong,
          source: _stereo);
      expect(p.af, contains('equalizer=f=1000:t=q:w=1:g=12.0'),
          reason: '11 + 3 × 1.5 clamps to +12');
      expect(p.af, contains('equalizer=f=31:t=q:w=1:g=-6.0'));
      expect(p.gainDb, 1 + voiceClarityCompensationDb * 1.5);
    });
  });

  test('AudioSource knows Dolby and multichannel', () {
    expect(const AudioSource(codec: 'ac3', channels: 6).isDolby, isTrue);
    expect(const AudioSource(codec: 'aac', channels: 6).isDolby, isFalse);
    expect(const AudioSource(channels: 2).isMultichannel, isFalse);
    expect(const AudioSource().isMultichannel, isFalse);
  });

  test('levels parse and fall back to medium', () {
    expect(EnhancementLevel.fromId('strong'), EnhancementLevel.strong);
    expect(EnhancementLevel.fromId('bogus'), EnhancementLevel.medium);
  });
}
