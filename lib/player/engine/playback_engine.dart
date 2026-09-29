import '../chapters/chapter.dart';

/// A single audio or subtitle track, decoupled from media_kit's own
/// [AudioTrack]/[SubtitleTrack] types so they never leak past this file.
class MediaTrack {
  final String id;
  final String? title;
  final String? language;
  final bool isDefault;

  /// mpv's codec name (`subrip`, `ass`, `hdmv_pgs_subtitle`, `eac3`, …),
  /// or null when the container did not say.
  final String? codec;
  const MediaTrack({
    required this.id,
    this.title,
    this.language,
    this.isDefault = false,
    this.codec,
  });

  @override
  bool operator ==(Object other) => other is MediaTrack && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

abstract class PlaybackEngine {
  dynamic get nativePlayer;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<bool> get completedStream;

  /// Emits true once the currently-open media has a decoded video frame, and
  /// false while a (re)open is in flight (no frame yet). Backed by the video
  /// width: media_kit resets it to null on every open and sets it when the
  /// first frame's params are known. The UI uses this to cover the shared
  /// texture's stale last-frame across an open. Events that arrive while the
  /// video output is intentionally off (see [setVideoTrackEnabled]) are
  /// dropped — the cover belongs to the open sequence, not to mpv's `vid`.
  Stream<bool> get hasVideoFrameStream;

  /// Returns a platform video controller (e.g. [VideoController] from
  /// package:media_kit_video) or null if no video surface is available.
  /// The return type is [Object?] so the UI layer can do `is VideoController`
  /// without importing package:media_kit.
  Object? createVideoController();

  Future<void> open(String path, {Duration startAt});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> setVolume(double percent);
  Future<void> dispose();

  Stream<List<MediaTrack>> get audioTracksStream;
  Stream<List<MediaTrack>> get subtitleTracksStream;
  Stream<MediaTrack?> get currentAudioTrackStream;
  Stream<MediaTrack?> get currentSubtitleTrackStream; // null = off

  /// Current track snapshots (what `_player.state` holds right now), used as
  /// `initialData` for the picker so it never shows empty when the underlying
  /// broadcast stream already emitted before the panel subscribed.
  List<MediaTrack> get currentSubtitleTracks;
  List<MediaTrack> get currentAudioTracks;
  MediaTrack? get currentSubtitleTrack; // null = off
  MediaTrack? get currentAudioTrack;

  Future<void> setAudioTrack(String id);
  Future<void> setSubtitleTrack(String? id); // null = turn off
  /// Adds [uri] as a subtitle track and selects it. With [replaceCurrent] the
  /// currently selected subtitle track is removed first — for re-loading the
  /// same external file (e.g. in another encoding) without the track list
  /// growing one duplicate per attempt. Only pass it when the current track is
  /// an external one: mpv removes whatever is selected.
  Future<void> setExternalSubtitle(String uri,
      {String? title, bool replaceCurrent = false});

  /// Sets mpv's `hwdec` (e.g. `auto-safe`, `no`). A global option on the
  /// process-lifetime player that survives `loadfile`, so the caller writes it
  /// on EVERY open, never only when it changes. Can be changed mid-playback:
  /// mpv reinitialises the decoder and keeps position and tracks.
  ///
  /// Same UI-thread hazard as [setSubtitleDelay]: once per open or per user
  /// switch, never in a loop.
  Future<void> setHwdec(String value);

  /// What mpv is actually decoding with right now (`hwdec-current`):
  /// e.g. `mediacodec-copy`, `no` for software, or null when nothing is loaded
  /// or the property cannot be read.
  Future<String?> activeHwdec();

  /// Whether the open media has a real video track (not audio-only).
  bool get hasVideoTrack;

  /// False while [setVideoTrackEnabled] has turned the video output off
  /// (background / audio-only mode).
  bool get videoOutputEnabled;

  /// Emits [videoOutputEnabled] each time [setVideoTrackEnabled] changes it.
  Stream<bool> get videoOutputEnabledStream;

  /// Shifts subtitle timing. Positive = subtitles appear later, matching
  /// mpv's own `sub-delay` sign.
  ///
  /// Callers MUST debounce: this is a synchronous mpv call on the UI thread,
  /// the same one at the top of the open background-hang ANR trace. One call
  /// per gesture burst, never one per tap.
  Future<void> setSubtitleDelay(double seconds);

  /// Shifts audio timing against the video. Positive = audio plays later,
  /// matching mpv's own `audio-delay` sign.
  ///
  /// Same debounce contract as [setSubtitleDelay], and the same hazard.
  Future<void> setAudioDelay(double seconds);

  /// Sets mpv's `af` (audio filter) property directly — the equalizer's only
  /// touchpoint with mpv. Pass the empty string to clear the filter graph.
  /// See `EqualizerSettings`/`mpvAudioFilter` in
  /// `lib/player/audio/equalizer.dart` for what builds the value.
  ///
  /// Same debounce contract as [setSubtitleDelay]/[setAudioDelay]: a
  /// synchronous mpv call on the UI thread. One call per slider settle,
  /// never one per tick.
  Future<void> setAudioFilter(String af);

  /// A plain software gain in dB (mpv `replaygain-fallback`, which applies
  /// whenever ReplayGain mode is off — always, in Kivo). The equalizer preamp
  /// lives here because the bundled FFmpeg has no `volume` filter.
  ///
  /// Written only by `AudioPipelineController`; same UI-thread budget as
  /// [setAudioFilter].
  Future<void> setAudioGain(double db);

  /// Downmix control: [forceStereo] sets `audio-channels` to `stereo`
  /// (otherwise mpv's `auto-safe`), [swresample] is the
  /// `audio-swresample-o` list ('' = swresample defaults). Both reload mpv's
  /// audio chain, so only `AudioPipelineController` writes them, and only
  /// when they change.
  Future<void> setAudioDownmix({required bool forceStereo, required String swresample});

  /// Dolby dynamic range compression scale for AC-3/E-AC-3 (mpv
  /// `ad-lavc-ac3drc`, 0 = off). Read by the decoder at init only — see
  /// [reloadAudioDecoder].
  ///
  /// [heavyCompression] also asks for the stream's "heavy" compression words
  /// (FFmpeg `heavy_compr`, via mpv `ad-lavc-o`), same init-only rule.
  Future<void> setDolbyDrc(double scale, {bool heavyCompression = false});

  /// Re-creates the current audio track's decoder (deselect and reselect it),
  /// so a decoder-init option like [setDolbyDrc] takes effect mid-playback.
  /// A sub-second audio gap.
  Future<void> reloadAudioDecoder();

  /// Codec and channel count of the audio track actually playing (mpv
  /// `current-tracks/audio/*`), or null when there is none or it cannot be
  /// read yet.
  Future<({String? codec, int? channels})?> currentAudioSource();

  /// The video's own chapter marks, or empty when it has none.
  ///
  /// Read on demand rather than kept live: media_kit does not surface
  /// chapters, so this walks mpv's chapter-list one property at a time, and
  /// doing that during a video open would land dozens of synchronous FFI
  /// calls on the UI thread at the busiest moment there is.
  Future<List<MediaChapter>> chapters();

  /// mpv's current plain subtitle text: [primary, secondary] (`sub-text`,
  /// `secondary-sub-text`), '' when nothing is showing. What Kivo's own
  /// subtitle overlay draws.
  Stream<List<String>> get subtitleTextStream;
  List<String> get currentSubtitleText;

  /// Codec of the subtitle track actually selected (`current-tracks/sub/codec`),
  /// or null when none is or it cannot be read yet.
  Future<String?> currentSubtitleCodec();

  /// Whether mpv draws the current subtitle into the video (`sub-visibility`).
  /// Off whenever Kivo's overlay draws it instead — see `drawerFor`.
  Future<void> setSubtitleRendering({required bool mpvDraws});

  /// Gives libass the one font it can use on Android (no font provider in this
  /// build): `sub-fonts-dir` + `sub-font`, and turns ASS styling on
  /// (`sub-ass=yes`, `sub-ass-override=no`, i.e. the file's own style).
  Future<void> configureSubtitleFonts({required String dir, required String family});

  /// Selects the secondary subtitle track (`secondary-sid`), or turns it off
  /// with null. A global mpv option that survives loadfile: write it on every
  /// open.
  Future<void> setSecondarySubtitleTrack(String? id);

  /// Releases mpv's video output ([enabled] = false → `vid=no`) or reattaches it
  /// (true → `vid=auto`). Used around the background round-trip so a live video
  /// output is never left holding a surface Android is about to destroy.
  Future<void> setVideoTrackEnabled(bool enabled);

  /// Safety net for the background round-trip: if mpv has not brought its video
  /// output back shortly after [setVideoTrackEnabled]`(true)`, nudge it once.
  /// Fire-and-forget — never await this from UI code.
  Future<void> ensureVideoOutputAttached();

  /// Current video pixel dimensions, or null if unknown (used for the PiP
  /// window aspect ratio).
  ({int width, int height})? get videoSize;
}
