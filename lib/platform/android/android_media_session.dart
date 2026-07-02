import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../interfaces/media_session.dart';

class AndroidMediaSessionBridge implements MediaSessionBridge {
  static const _channel = MethodChannel('kivo/media_session');
  MediaSessionCallbacks? _callbacks;
  bool _permissionRequested = false;

  AndroidMediaSessionBridge() {
    _channel.setMethodCallHandler((call) async {
      final cb = _callbacks;
      if (cb == null) return;
      switch (call.method) {
        case 'play':
          cb.onPlay();
        case 'pause':
          cb.onPause();
        case 'skip':
          cb.onSkip((call.arguments as Map)['seconds'] as int);
        case 'seekTo':
          cb.onSeek(Duration(milliseconds: (call.arguments as Map)['ms'] as int));
        case 'stop':
          cb.onStop();
        case 'focusLoss':
          cb.onFocusLoss();
        case 'focusTransientLoss':
          cb.onFocusTransientLoss();
        case 'focusRegained':
          cb.onFocusRegained();
        case 'duckStart':
          cb.onDuckStart();
        case 'duckEnd':
          cb.onDuckEnd();
      }
    });
  }

  @override
  void setCallbacks(MediaSessionCallbacks callbacks) => _callbacks = callbacks;

  @override
  Future<void> ensureNotificationPermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    // Denial is non-fatal: background audio still works, only the
    // notification is missing.
    await Permission.notification.request();
  }

  @override
  Future<void> updateSession({
    required String title,
    required String mediaUri,
    required Duration position,
    required Duration duration,
    required bool playing,
    required bool inBackground,
  }) {
    return _channel.invokeMethod('update', {
      'title': title,
      'mediaUri': mediaUri,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'playing': playing,
      'inBackground': inBackground,
    });
  }

  @override
  Future<void> endSession() => _channel.invokeMethod('end');
}
