abstract class PlaybackEngine {
  dynamic get nativePlayer;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;

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
}
