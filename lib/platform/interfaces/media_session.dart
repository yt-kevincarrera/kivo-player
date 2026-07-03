/// Callbacks the native media session / audio-focus side invokes on Dart.
class MediaSessionCallbacks {
  final void Function() onPlay;
  final void Function() onPause;
  final void Function(int seconds) onSkip;
  final void Function(Duration position) onSeek;
  final void Function() onStop;
  final void Function() onFocusLoss;
  final void Function() onFocusTransientLoss;
  final void Function() onFocusRegained;
  final void Function() onDuckStart;
  final void Function() onDuckEnd;
  const MediaSessionCallbacks({
    required this.onPlay,
    required this.onPause,
    required this.onSkip,
    required this.onSeek,
    required this.onStop,
    required this.onFocusLoss,
    required this.onFocusTransientLoss,
    required this.onFocusRegained,
    required this.onDuckStart,
    required this.onDuckEnd,
  });
}

/// Boundary to the Android media session + notification + audio focus.
abstract class MediaSessionBridge {
  void setCallbacks(MediaSessionCallbacks callbacks);

  /// Android 13+ runtime notification permission. Safe to call repeatedly.
  Future<void> ensureNotificationPermission();

  /// Pushed on every playing-state change, every new position second while
  /// relevant, and every lifecycle change. Native decides from [playing] +
  /// [inBackground] whether a foreground service/notification must exist.
  /// [mediaUri] lets the native side load the video's thumbnail itself for
  /// the notification artwork (content:// or file path; cached per uri).
  Future<void> updateSession({
    required String title,
    required String mediaUri,
    required Duration position,
    required Duration duration,
    required bool playing,
    required bool inBackground,
  });

  Future<void> endSession();

  /// Acquire AUDIOFOCUS_GAIN for playback (foreground included). Idempotent.
  /// Held so that a phone call or another app taking focus routes through the
  /// focus callbacks and pauses Kivo instead of leaving it playing.
  Future<void> acquireAudioFocus();

  /// Abandon audio focus. Called on a user-driven pause — never on a
  /// focus-driven one, which must keep focus so the later GAIN auto-resumes.
  Future<void> releaseAudioFocus();
}
