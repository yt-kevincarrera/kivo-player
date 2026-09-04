/// Ten-band parametric equalizer model for Kivo's mpv-backed audio pipeline.
///
/// mpv (via ffmpeg's `equalizer` lavfi filter) does the actual filtering —
/// this file only models the ten fixed bands, builds the `af` string mpv
/// consumes, and defines the named presets. See
/// [PlaybackEngine.setAudioFilter] for where the string lands, and
/// `equalizer_controller.dart` for how it gets there without hammering mpv
/// on every slider tick.
library;

/// Center frequencies (Hz) of the ten fixed bands, low to high. Index order
/// here is the index order everywhere else — [EqualizerSettings.gainsDb],
/// preset curves, the slider row.
const List<int> equalizerBandsHz = [
  31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
];

const double equalizerMinDb = -12.0;
const double equalizerMaxDb = 12.0;
const double equalizerStepDb = 0.5;

double clampEqualizerDb(double db) => db.clamp(equalizerMinDb, equalizerMaxDb);

bool _gainsEqual(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One EQ curve: ten band gains plus an overall preamp, and whether any of
/// it is actually applied right now.
class EqualizerSettings {
  final bool enabled;
  final double preampDb;

  /// One gain per [equalizerBandsHz] entry, same order, length 10.
  final List<double> gainsDb;

  const EqualizerSettings({
    required this.enabled,
    required this.preampDb,
    required this.gainsDb,
  });

  factory EqualizerSettings.flat({bool enabled = false}) => EqualizerSettings(
        enabled: enabled,
        preampDb: 0,
        gainsDb: List.filled(equalizerBandsHz.length, 0.0),
      );

  EqualizerSettings copyWith({
    bool? enabled,
    double? preampDb,
    List<double>? gainsDb,
  }) =>
      EqualizerSettings(
        enabled: enabled ?? this.enabled,
        preampDb: preampDb ?? this.preampDb,
        gainsDb: gainsDb ?? this.gainsDb,
      );

  /// [gainsDb] with just band [index] replaced — the shape every slider drag
  /// needs, clamped to the same range the UI enforces.
  EqualizerSettings withBand(int index, double db) {
    final next = List<double>.of(gainsDb);
    next[index] = clampEqualizerDb(db);
    return copyWith(gainsDb: next);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EqualizerSettings &&
          other.enabled == enabled &&
          other.preampDb == preampDb &&
          _gainsEqual(other.gainsDb, gainsDb));

  @override
  int get hashCode => Object.hash(enabled, preampDb, Object.hashAll(gainsDb));

  // Short keys: this rides inside KivoSettings' own map on every save.
  Map<String, dynamic> toMap() => {
        'on': enabled,
        'pre': preampDb,
        'g': gainsDb,
      };

  /// Tolerant of a missing/wrong-shaped map (falls back to flat+disabled),
  /// unknown extra keys, and a stored gains list of the wrong length — which
  /// falls back to a flat curve rather than misaligning a band onto the
  /// wrong frequency or throwing on a corrupted settings file.
  factory EqualizerSettings.fromMap(dynamic raw) {
    final m = raw is Map ? raw : null;
    if (m == null) return EqualizerSettings.flat();
    final rawGains = m['g'];
    final gains = rawGains is List && rawGains.length == equalizerBandsHz.length
        ? rawGains.map((e) => (e as num).toDouble()).toList()
        : List<double>.filled(equalizerBandsHz.length, 0.0);
    return EqualizerSettings(
      enabled: m['on'] as bool? ?? false,
      preampDb: (m['pre'] as num?)?.toDouble() ?? 0.0,
      gainsDb: gains,
    );
  }
}

/// Curves offered in the presets row, keyed by display name.
///
/// - Plano: every band at 0 dB — the neutral starting point.
/// - Graves: a strong lift on 31/62 Hz tapering off by 250 Hz, flat from the
///   mids up so vocals don't get buried under the extra bass.
/// - Voz: a mild cut on rumble and sibilance (31/62 Hz, 16 kHz) with a lift
///   centered on 1-2 kHz, where consonants and vocal presence live — meant
///   for dialogue-heavy video with a thin or muddy mix.
/// - Agudos: flat through the bass and low mids, rising steadily above 1 kHz
///   for more "air" and detail on the top end.
final Map<String, List<double>> equalizerPresetCurves = {
  'Plano': List.filled(equalizerBandsHz.length, 0.0),
  'Graves': const [6.0, 5.0, 3.5, 1.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  'Voz': const [-3.0, -2.0, 0.0, 1.0, 3.0, 4.0, 3.0, 2.0, 0.0, -1.0],
  'Agudos': const [0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 1.5, 3.0, 5.0, 6.0],
};

/// Preset names in display order, for the chips row.
const List<String> equalizerPresetNames = ['Plano', 'Graves', 'Voz', 'Agudos'];

/// The preset whose curve matches [settings.gainsDb] exactly, or
/// 'Personalizado' when the user has hand-tuned away from every preset.
/// Preamp and enabled play no part in the match — a preset stays "itself"
/// whether or not preamp is dialed in or the switch is off, since those are
/// separate controls from the curve itself.
///
/// Kept for any caller still on the Spanish-string API; [presetFor] is the
/// localized-UI replacement (see `settingsEqPreset*` in the ARB) and shares
/// this function's matching loop.
String presetNameFor(EqualizerSettings settings) {
  for (final name in equalizerPresetNames) {
    if (_gainsEqual(settings.gainsDb, equalizerPresetCurves[name]!)) {
      return name;
    }
  }
  return 'Personalizado';
}

/// Structured counterpart to [equalizerPresetNames]' Spanish strings, in the
/// same display order, plus [custom] for a hand-tuned curve. A UI maps each
/// value to `context.l10n.settingsEqPreset*` rather than showing [name]
/// directly.
enum EqPreset {
  flat('Plano'),
  bass('Graves'),
  voice('Voz'),
  treble('Agudos'),
  custom('Personalizado');

  /// The internal Spanish identifier this preset corresponds to in
  /// [equalizerPresetCurves] / [equalizerPresetNames] — what
  /// `EqualizerController.applyPreset` still takes. Never shown in the UI.
  final String name;
  const EqPreset(this.name);
}

/// [EqPreset] equivalent of [presetNameFor] — the preset whose curve matches
/// [settings.gainsDb] exactly, or [EqPreset.custom] when hand-tuned away from
/// every preset.
EqPreset presetFor(EqualizerSettings settings) {
  for (final preset in EqPreset.values) {
    if (preset == EqPreset.custom) continue;
    if (_gainsEqual(settings.gainsDb, equalizerPresetCurves[preset.name]!)) {
      return preset;
    }
  }
  return EqPreset.custom;
}

/// Builds the exact `af` mpv property value for [settings].
///
/// Empty when disabled, or when enabled but perfectly flat with no preamp —
/// mpv drops the audio filter graph entirely rather than running a set of
/// no-op band filters on every frame. Otherwise a `lavfi` graph chaining all
/// ten bands (even the ones left at 0 dB — the graph shape stays constant so
/// nothing has to special-case which bands are "on") plus an extra `volume`
/// stage when preamp is non-zero.
///
/// Fixed-point (`toStringAsFixed(1)`) formatting keeps the string stable
/// across calls for the same settings, matching [EqualizerSettings]' own
/// 0.5 dB step.
String mpvAudioFilter(EqualizerSettings settings) {
  final isFlat = settings.gainsDb.every((g) => g == 0.0);
  if (!settings.enabled || (isFlat && settings.preampDb == 0.0)) return '';

  final stages = <String>[
    for (var i = 0; i < equalizerBandsHz.length; i++)
      'equalizer=f=${equalizerBandsHz[i]}:t=q:w=1:g=${settings.gainsDb[i].toStringAsFixed(1)}',
    if (settings.preampDb != 0.0)
      'volume=${settings.preampDb.toStringAsFixed(1)}dB',
  ];
  return 'lavfi=[${stages.join(',')}]';
}
