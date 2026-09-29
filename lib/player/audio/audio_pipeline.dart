import 'dart:math' as math;

import 'equalizer.dart';

/// How strong Modo noche / Realzar voces act. Stored as [id].
enum EnhancementLevel {
  soft('soft', 0.5, drcScale: 0.5, heavyCompression: false, centerMix: 1.0),
  medium('medium', 1.0,
      drcScale: 1.0, heavyCompression: false, centerMix: 1.41),
  strong('strong', 1.5,
      drcScale: 1.0, heavyCompression: true, centerMix: 2.0);

  const EnhancementLevel(this.id, this.curveFactor,
      {required this.drcScale,
      required this.heavyCompression,
      required this.centerMix});

  final String id;

  /// Scales [voiceClarityCurve] for stereo sources.
  final double curveFactor;

  /// FFmpeg `drc_scale` for AC-3/E-AC-3 (mpv `ad-lavc-ac3drc`): 1 is the
  /// compression exactly as the Dolby stream authored it, 0.5 half of it.
  /// Never above 1: FFmpeg then only raises the *boost* words (quiet passages
  /// get louder, hiss and pumping come up) while the peaks stay exactly
  /// where 1.0 puts them — the opposite of what Modo noche promises.
  final double drcScale;

  /// FFmpeg `heavy_compr` (via mpv `ad-lavc-o`): the stream's own "heavy"
  /// compression words, meant for exactly this. Streams without them fall
  /// back to the normal DRC data, so it is never worse than [drcScale] 1.
  final bool heavyCompression;

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

/// swresample's own downmix level for the centre and the surrounds (−3 dB).
const double defaultDownmixMix = 0.707;

/// Gain (dB) that keeps the loudest possible sample of a centre-raised
/// downmix where mpv's default downmix already puts it. mpv does not
/// normalise the matrix (rematrix_maxval=1000), so L = FL + c·FC + s·SL can
/// pass full scale; this takes back only what raising the centre added over
/// the default, so the dialogue still ends up louder than the effects.
double downmixHeadroomDb(double centerMix) {
  const base = 1 + defaultDownmixMix + defaultDownmixMix;
  final boosted = 1 + centerMix + voiceBoostSurroundMix;
  if (boosted <= base) return 0;
  return -20 * math.log(boosted / base) / math.ln10;
}

/// Every audio-related mpv value Kivo controls, for one moment in playback.
class AudioPipeline {
  const AudioPipeline({
    required this.af,
    required this.gainDb,
    required this.forceStereo,
    required this.swresample,
    required this.drc,
    this.heavyCompression = false,
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

  /// mpv `ad-lavc-o=heavy_compr=1` when true, '' otherwise.
  final bool heavyCompression;

  @override
  bool operator ==(Object other) =>
      other is AudioPipeline &&
      other.af == af &&
      other.gainDb == gainDb &&
      other.forceStereo == forceStereo &&
      other.swresample == swresample &&
      other.drc == drc &&
      other.heavyCompression == heavyCompression;

  @override
  int get hashCode =>
      Object.hash(af, gainDb, forceStereo, swresample, drc, heavyCompression);

  @override
  String toString() => 'AudioPipeline(af: $af, gain: $gainDb, '
      'stereo: $forceStereo, swr: $swresample, drc: $drc, '
      'heavy: $heavyCompression)';
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
  } else if (voiceBoost) {
    gain += downmixHeadroomDb(voiceLevel.centerMix);
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
    heavyCompression: nightMode && nightLevel.heavyCompression,
  );
}
