import 'equalizer.dart';

/// How strong Modo noche / Realzar voces act. Stored as [id].
enum EnhancementLevel {
  soft('soft', 0.5, drcScale: 1.0, centerMix: 1.0),
  medium('medium', 1.0, drcScale: 2.0, centerMix: 1.41),
  strong('strong', 1.5, drcScale: 4.0, centerMix: 2.0);

  const EnhancementLevel(this.id, this.curveFactor,
      {required this.drcScale, required this.centerMix});

  final String id;

  /// Scales [voiceClarityCurve] for stereo sources.
  final double curveFactor;

  /// FFmpeg `drc_scale` for AC-3/E-AC-3 (mpv `ad-lavc-ac3drc`): 1 is the
  /// compression exactly as the Dolby stream authored it; more exaggerates it.
  final double drcScale;

  /// swresample `center_mix_level` when downmixing to stereo. Its own default
  /// is 0.707 (−3 dB): above that the centre channel — where film dialogue
  /// lives — comes out louder than the effects around it.
  final double centerMix;

  static EnhancementLevel fromId(String? id) => EnhancementLevel.values
      .firstWhere((l) => l.id == id, orElse: () => EnhancementLevel.medium);
}

/// What is known about the audio track playing, from its container.
class AudioSource {
  const AudioSource({this.codec, this.channels});

  /// mpv's codec name (`ac3`, `eac3`, `aac`, …).
  final String? codec;
  final int? channels;

  /// Carries the Dolby dynamic range metadata `ad-lavc-ac3drc` acts on.
  bool get isDolby => codec == 'ac3' || codec == 'eac3';

  /// More than stereo: the dialogue has its own centre channel to raise.
  bool get isMultichannel => (channels ?? 0) > 2;

  @override
  bool operator ==(Object other) =>
      other is AudioSource && other.codec == codec && other.channels == channels;

  @override
  int get hashCode => Object.hash(codec, channels);
}

/// Surround level used while raising the centre: the ambience steps back so
/// the dialogue stands out from it too (swresample's default is 0.707).
const double voiceBoostSurroundMix = 0.5;

/// Band gains (dB) for dialogue clarity on a stereo track, at medium: rumble
/// and bass down, the 1–4 kHz presence range up. There is no centre channel to
/// raise in stereo, so this is the next best thing the one available filter
/// (equalizer) can do.
const List<double> voiceClarityCurve = [
  -4.0, -3.0, -1.5, 0.0, 1.5, 3.0, 3.0, 2.0, 0.0, 0.0, //
];

/// Gain (dB) that keeps [voiceClarityCurve]'s boost from clipping, at medium.
const double voiceClarityCompensationDb = -1.5;

/// Every audio-related mpv value Kivo controls, for one moment in playback.
class AudioPipeline {
  const AudioPipeline({
    required this.af,
    required this.gainDb,
    required this.forceStereo,
    required this.swresample,
    required this.drc,
  });

  /// mpv `af`: the equalizer chain or ''.
  final String af;

  /// mpv `replaygain-fallback`: a plain software gain (ReplayGain itself is
  /// off, so the fallback is always what applies).
  final double gainDb;

  /// mpv `audio-channels`: `stereo` when true, `auto-safe` (mpv's default)
  /// otherwise.
  final bool forceStereo;

  /// mpv `audio-swresample-o`, or '' for swresample's defaults.
  final String swresample;

  /// mpv `ad-lavc-ac3drc`.
  final double drc;

  @override
  bool operator ==(Object other) =>
      other is AudioPipeline &&
      other.af == af &&
      other.gainDb == gainDb &&
      other.forceStereo == forceStereo &&
      other.swresample == swresample &&
      other.drc == drc;

  @override
  int get hashCode => Object.hash(af, gainDb, forceStereo, swresample, drc);

  @override
  String toString() => 'AudioPipeline(af: $af, gain: $gainDb, '
      'stereo: $forceStereo, swr: $swresample, drc: $drc)';
}

/// Composes the equalizer, Modo noche and Realzar voces into mpv values.
///
/// [source] may be null while the track is not known yet (just after an
/// open); it is then treated as stereo and recomputed when it arrives.
AudioPipeline buildAudioPipeline({
  required EqualizerSettings equalizer,
  required bool nightMode,
  required EnhancementLevel nightLevel,
  required bool voiceBoost,
  required EnhancementLevel voiceLevel,
  AudioSource? source,
}) {
  final bands = List<double>.of(equalizer.enabled
      ? equalizer.gainsDb
      : List<double>.filled(equalizerBandsHz.length, 0.0));
  var gain = equalizer.enabled ? equalizer.preampDb : 0.0;

  final multichannel = source?.isMultichannel ?? false;
  if (voiceBoost && !multichannel) {
    for (var i = 0; i < bands.length; i++) {
      bands[i] = clampEqualizerDb(
          bands[i] + voiceClarityCurve[i] * voiceLevel.curveFactor);
    }
    gain += voiceClarityCompensationDb * voiceLevel.curveFactor;
  }

  return AudioPipeline(
    af: mpvEqualizerFilter(bands),
    gainDb: gain,
    // Written whenever the feature is on, whatever the source: switching
    // between a stereo and a 5.1 track then never reloads mpv's audio chain
    // just to change these (both are UPDATE_AUDIO options).
    forceStereo: voiceBoost,
    swresample: voiceBoost
        ? 'center_mix_level=${voiceLevel.centerMix},'
            'surround_mix_level=$voiceBoostSurroundMix'
        : '',
    drc: nightMode ? nightLevel.drcScale : 0.0,
  );
}
