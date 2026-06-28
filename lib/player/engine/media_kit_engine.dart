import 'package:media_kit/media_kit.dart';
import 'playback_engine.dart';

class MediaKitEngine implements PlaybackEngine {
  final Player _player = Player();

  @override
  dynamic get nativePlayer => _player;
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
