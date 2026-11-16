import '../engine/video_progress.dart';

/// A static picture is only a decoder failure when its timestamp is static
/// while the audio/playback clock keeps moving. A slow but advancing 4K stream,
/// a pause, an exact seek, or disabled output must not trigger software mode.
class VideoProgressWatchdog {
  VideoProgress? _anchor;
  bool _fired = false;
  void reset() {
    _anchor = null;
    _fired = false;
  }

  bool update(
    VideoProgress sample, {
    required Duration timeout,
    required bool enabled,
  }) {
    if (!enabled ||
        sample.paused ||
        sample.seeking ||
        sample.position == null ||
        sample.videoPosition == null) {
      reset();
      return false;
    }
    if (_fired) return false;
    final anchor = _anchor;
    if (anchor == null ||
        sample.videoPosition != anchor.videoPosition ||
        sample.position! < anchor.position! ||
        sample.sampledAt < anchor.sampledAt) {
      _anchor = sample;
      return false;
    }
    if (sample.sampledAt - anchor.sampledAt < timeout ||
        sample.position! - anchor.position! < const Duration(seconds: 1)) {
      return false;
    }
    _fired = true;
    return true;
  }
}
