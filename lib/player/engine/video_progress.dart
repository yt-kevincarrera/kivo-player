/// Independent audio and video progress. mpv 0.36 time-pos follows the video
/// while it is active; audio-pts reads the running audio clock separately.
/// [sampledAt] is monotonic wall time, not a wall-clock date.
class VideoProgress {
  const VideoProgress({
    required this.position,
    required this.videoPosition,
    required this.sampledAt,
    this.paused = false,
    this.seeking = false,
  });
  final Duration? position;
  final Duration? videoPosition;
  final Duration sampledAt;
  final bool paused;
  final bool seeking;
}
