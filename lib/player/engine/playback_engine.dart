/// A single audio or subtitle track, decoupled from media_kit's own
/// [AudioTrack]/[SubtitleTrack] types so they never leak past this file.
class MediaTrack {
  final String id;
  final String? title;
  final String? language;
  final bool isDefault;
  const MediaTrack({
    required this.id,
    this.title,
    this.language,
    this.isDefault = false,
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
  /// texture's stale last-frame across an open. Stays false for audio-only.
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
  Future<void> setExternalSubtitle(String uri, {String? title});

  Future<void> setSubtitleStyle({
    required double fontSize,
    required int textColorArgb,
    required int backgroundColorArgb,
  });

  /// Turns the video track off ([enabled] = false → mpv `vid=no`, audio-only)
  /// or back to automatic selection (true → `vid=auto`).
  Future<void> setVideoTrackEnabled(bool enabled);

  /// Current video pixel dimensions, or null if unknown (used for the PiP
  /// window aspect ratio).
  ({int width, int height})? get videoSize;
}
