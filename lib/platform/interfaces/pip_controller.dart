/// Callbacks the native PiP window invokes on Dart.
class PipCallbacks {
  final void Function(bool inPip) onModeChanged;
  final void Function() onPlay;
  final void Function() onPause;
  final void Function(int seconds) onSkip;
  const PipCallbacks({
    required this.onModeChanged,
    required this.onPlay,
    required this.onPause,
    required this.onSkip,
  });
}

/// Boundary to Android Picture-in-Picture.
abstract class PipController {
  /// True on API 26+ devices that support PiP.
  Future<bool> isSupported();

  void setCallbacks(PipCallbacks cb);

  /// Enable auto-enter-on-Home with the current video size + playing state.
  Future<void> arm({required int width, required int height, required bool playing});

  /// Disable auto-enter (leaving the player).
  Future<void> disarm();

  /// Enter PiP immediately (the top-bar button).
  Future<void> enterNow();

  /// Refresh the window aspect ratio (size) and the play/pause action (playing).
  Future<void> updateState({required int width, required int height, required bool playing});
}
