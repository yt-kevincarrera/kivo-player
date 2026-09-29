/// Which decoder a video plays with. Stored as [id] — in
/// `KivoSettings.decoderMode` (the default) and `VideoTrackPrefs.decoder`
/// (one video's override).
enum DecoderMode {
  /// Hardware, with Kivo's watchdog switching to software when no frame
  /// arrives. The default.
  auto('auto', 'auto-safe', watched: true),

  /// Hardware without Kivo's watchdog. mpv still falls back to software on
  /// its own when the hardware decoder cannot even start.
  hardware('hw', 'auto-safe', watched: false),

  /// Software decoding: slowest and most battery-hungry, but it plays what
  /// the phone's MediaCodec cannot.
  software('sw', 'no', watched: false);

  const DecoderMode(this.id, this.mpvHwdec, {required this.watched});

  final String id;

  /// The value written to mpv's `hwdec`.
  final String mpvHwdec;

  /// Whether the stall watchdog applies.
  final bool watched;

  static DecoderMode fromId(String? id) => DecoderMode.values
      .firstWhere((m) => m.id == id, orElse: () => DecoderMode.auto);
}

/// The mode a video plays with: its own override, else the global default.
DecoderMode resolveDecoderMode({required String global, String? perVideo}) =>
    DecoderMode.fromId(perVideo ?? global);

/// What to store for a video when the user picks [chosen] in the player.
///
/// Null when [chosen] equals the global default, so "saved for this video"
/// always means "differs from your default" — and changing the default later
/// still reaches every video the user never singled out.
String? overrideFor(DecoderMode chosen, {required String global}) =>
    chosen == DecoderMode.fromId(global) ? null : chosen.id;

/// Whether mpv's `hwdec-current` names a hardware decoder. mpv reports `no`
/// for software and nothing at all while no file is loaded.
bool isHardwareActive(String? hwdecCurrent) =>
    hwdecCurrent != null && hwdecCurrent.isNotEmpty && hwdecCurrent != 'no';
