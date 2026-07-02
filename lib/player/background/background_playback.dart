import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/interfaces/media_session.dart';
import '../../platform/media_session_provider.dart';
import '../control/gesture_math.dart';
import '../control/player_controller.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';

/// App-level coordinator: keeps the native media session fed while playback
/// is relevant, reacts to notification/focus events, and owns the duck.
/// Instantiate by watching [backgroundPlaybackProvider] once (KivoApp does).
final backgroundPlaybackProvider = Provider<BackgroundPlaybackCoordinator>((ref) {
  final coordinator = BackgroundPlaybackCoordinator(ref);
  coordinator.init();
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

class BackgroundPlaybackCoordinator with WidgetsBindingObserver {
  final Ref _ref;
  BackgroundPlaybackCoordinator(this._ref);

  bool _inBackground = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _lastSentSecond = -1;
  bool _sessionActive = false;

  bool _pausedByFocus = false;
  bool _ducking = false;
  bool _duckUserAdjusted = false;

  MediaSessionBridge get _bridge => _ref.read(mediaSessionProvider);

  void init() {
    WidgetsBinding.instance.addObserver(this);
    _bridge.setCallbacks(MediaSessionCallbacks(
      onPlay: () => _ref.read(playbackEngineProvider).play(),
      onPause: () => _ref.read(playbackEngineProvider).pause(),
      onSkip: (s) => _ref.read(playerControllerProvider).skipBy(s),
      onSeek: (p) => _ref.read(playerControllerProvider).seekTo(p),
      onStop: () {
        _ref.read(playbackEngineProvider).pause();
        _end();
      },
      onFocusLoss: _onFocusLoss,
      onFocusTransientLoss: _onFocusTransientLoss,
      onFocusRegained: _onFocusRegained,
      onDuckStart: _onDuckStart,
      onDuckEnd: _onDuckEnd,
    ));
    _ref.listen(playingProvider, (_, next) {
      final p = next.value;
      if (p == null) return;
      _playing = p;
      _push(force: true);
    });
    _ref.listen(positionProvider, (_, next) {
      final d = next.value;
      if (d == null) return;
      _position = d;
      _push();
    });
    _ref.listen(durationProvider, (_, next) {
      _duration = next.value ?? Duration.zero;
    });
    _ref.listen(volumePercentProvider, (_, __) {
      if (_ducking) _duckUserAdjusted = true;
    });
    _ref.listen(currentVideoProvider, (_, next) {
      // Ask for the notification permission at first video open — a request
      // from the background (session start) would never show the dialog.
      if (next != null && !_permissionAsked) {
        _permissionAsked = true;
        _bridge.ensureNotificationPermission();
      }
    });
  }

  bool _permissionAsked = false;

  void dispose() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _inBackground = true;
      _push(force: true);
    } else if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      if (_sessionActive) _end();
    }
  }

  void _push({bool force = false}) {
    final relevant = _playing || _sessionActive;
    if (!relevant) return;
    final second = _position.inSeconds;
    if (!force && second == _lastSentSecond) return;
    // Only feed the channel when a session exists or should start — in the
    // foreground with no session there is nothing to keep updated.
    final shouldHaveSession = _inBackground && _playing;
    if (!shouldHaveSession && !_sessionActive) return;
    _lastSentSecond = second;
    if (shouldHaveSession && !_sessionActive) {
      _sessionActive = true;
    }
    final title = _ref.read(currentVideoProvider)?.displayName ?? 'Kivo';
    _bridge.updateSession(
      title: title,
      position: _position,
      duration: _duration,
      playing: _playing,
      inBackground: _inBackground,
    );
  }

  void _end() {
    _sessionActive = false;
    _lastSentSecond = -1;
    _bridge.endSession();
  }

  // ── audio focus ──────────────────────────────────────────────────────────

  void _onFocusLoss() {
    if (_playing) _ref.read(playbackEngineProvider).pause();
    _pausedByFocus = false; // permanent: never auto-resume
  }

  void _onFocusTransientLoss() {
    if (_playing) {
      _ref.read(playbackEngineProvider).pause();
      _pausedByFocus = true;
    }
  }

  void _onFocusRegained() {
    if (_pausedByFocus) {
      _ref.read(playbackEngineProvider).play();
      _pausedByFocus = false;
    }
  }

  double get _userPlayerVolume {
    final boost = _ref.read(settingsProvider).volumeBoostMax.toDouble();
    return volumeMapping(_ref.read(volumePercentProvider), boost).playerPercent;
  }

  void _onDuckStart() {
    if (!_playing) return;
    _ducking = true;
    _duckUserAdjusted = false;
    _ref.read(playbackEngineProvider).setVolume(_userPlayerVolume * 0.3);
  }

  void _onDuckEnd() {
    if (_ducking && !_duckUserAdjusted) {
      _ref.read(playbackEngineProvider).setVolume(_userPlayerVolume);
    }
    _ducking = false;
    _duckUserAdjusted = false;
  }
}
