import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'playback_engine.dart';

/// Process-lifetime singleton engine.
///
/// [_player] and [_videoController] are intentionally never disposed by the
/// app: they live for the entire process lifetime. [VideoController] has no
/// public `dispose()` in media_kit_video 2.x — its native texture is released
/// only when the underlying [Player] is disposed, which happens automatically
/// when the process exits. Keeping a single cached [VideoController] ensures
/// exactly one native texture is allocated regardless of how many videos the
/// user opens in a session.
class MediaKitEngine implements PlaybackEngine {
  final Player _player = Player();

  /// Cached controller — created lazily on first call, reused for all opens.
  VideoController? _videoController;

  @override
  dynamic get nativePlayer => _player;

  @override
  Object? createVideoController() {
    _videoController ??= VideoController(_player);
    return _videoController;
  }

  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get durationStream => _player.stream.duration;
  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;
  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<bool> get hasVideoFrameStream =>
      _player.stream.width.map((w) => (w ?? 0) > 0);

  @override
  Future<void> open(String path, {Duration startAt = Duration.zero}) async {
    await _player.open(Media(path, start: startAt), play: true);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);
  @override
  Future<void> setVolume(double percent) => _player.setVolume(percent);
  @override
  Future<void> dispose() => _player.dispose();

  MediaTrack _audioToMedia(AudioTrack t) => MediaTrack(
        id: t.id,
        title: t.title,
        language: t.language,
        isDefault: t.isDefault ?? false,
      );

  MediaTrack? _subtitleToMedia(SubtitleTrack t) {
    // media_kit's pseudo-tracks: 'no' = explicitly off, 'auto' = nothing
    // selected (what a video with no subtitles reports). Both mean "no
    // subtitle showing" on this side of the boundary.
    if (t.id == 'no' || t.id == 'auto') return null;
    return MediaTrack(
      id: t.id,
      title: t.title,
      language: t.language,
      isDefault: t.isDefault ?? false,
    );
  }

  @override
  Stream<List<MediaTrack>> get audioTracksStream => _player.stream.tracks.map(
      (t) => t.audio
          .where((a) => a.id != 'auto' && a.id != 'no') // pseudo-tracks, not pickable rows
          .map(_audioToMedia)
          .toList());

  @override
  Stream<List<MediaTrack>> get subtitleTracksStream => _player.stream.tracks
      .map((t) => t.subtitle.map(_subtitleToMedia).whereType<MediaTrack>().toList());

  @override
  Stream<MediaTrack?> get currentAudioTrackStream =>
      _player.stream.track.map((t) => _audioToMedia(t.audio));

  @override
  Stream<MediaTrack?> get currentSubtitleTrackStream =>
      _player.stream.track.map((t) => _subtitleToMedia(t.subtitle));

  @override
  Future<void> setAudioTrack(String id) async {
    final track = _player.state.tracks.audio.firstWhere(
      (t) => t.id == id,
      orElse: () => AudioTrack.auto(),
    );
    await _player.setAudioTrack(track);
  }

  @override
  Future<void> setSubtitleTrack(String? id) async {
    if (id == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final track = _player.state.tracks.subtitle.firstWhere(
      (t) => t.id == id,
      orElse: () => SubtitleTrack.no(),
    );
    await _player.setSubtitleTrack(track);
  }

  @override
  Future<void> setExternalSubtitle(String uri, {String? title}) async {
    await _player.setSubtitleTrack(SubtitleTrack.uri(uri, title: title));
  }

  @override
  Future<void> setSubtitleStyle({
    required double fontSize,
    required int textColorArgb,
    required int backgroundColorArgb,
  }) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('sub-ass-override', 'force');
    await native.setProperty('sub-font-size', fontSize.toStringAsFixed(0));
    await native.setProperty('sub-color', _toMpvColor(textColorArgb));
    await native.setProperty('sub-back-color', _toMpvColor(backgroundColorArgb));
  }

  @override
  Future<void> setVideoTrackEnabled(bool enabled) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('vid', enabled ? 'auto' : 'no');
  }

  @override
  ({int width, int height})? get videoSize {
    final w = _player.state.width;
    final h = _player.state.height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return (width: w, height: h);
  }

  String _toMpvColor(int argb) {
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${hex(a)}${hex(r)}${hex(g)}${hex(b)}';
  }
}
