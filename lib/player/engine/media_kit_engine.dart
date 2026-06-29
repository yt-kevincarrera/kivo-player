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
}
