import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/interfaces/media_session.dart';
import '../../platform/media_session_provider.dart';
import '../../ui/player/state/pip_state.dart';
import '../control/gesture_math.dart';
import '../control/player_controller.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';
import 'audio_only.dart';

/// Whether a foreground media session should exist right now. It must exist
/// while a video is loaded and we're backgrounded (playing OR paused) so the
/// process stays foreground-protected and Android can't partially reclaim it —
/// except in PiP, where the floating window owns the controls.
bool shouldHaveMediaSession({
  required bool inBackground,
  required bool hasVideo,
  required bool inPip,
}) =>
    inBackground && hasVideo && !inPip;

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
      final was = _playing;
      _playing = p;
      // Hold audio focus the whole time we're playing — foreground included,
      // not just while a background session exists. Without this a phone call
      // in the foreground never reaches our focus listener, so the video keeps
      // playing (system-ducked and stuttering) instead of pausing. Release on a
      // user-driven pause; KEEP it through a focus-driven pause so the GAIN that
      // ends the call can auto-resume.
      if (p && !was) {
        _bridge.acquireAudioFocus();
      } else if (!p && was && !_pausedByFocus && !_ducking) {
        _bridge.releaseAudioFocus();
      }
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
    _ref.listen(pipModeProvider, (_, inPip) {
      // Entering PiP: the floating window owns the controls, so tear down any
      // media-session notification. The lifecycle `paused` and the PiP
      // `modeChanged` events race on Home-press; if `paused` won and started a
      // session before `pipMode` flipped, `_push`'s gate can't undo it — this
      // does.
      if (inPip && _sessionActive) _end();
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
      // Ending the session abandons audio focus natively; if we're still
      // playing in the foreground, take it straight back so a phone call after
      // a background round-trip still pauses us instead of ducking.
      if (_playing) _bridge.acquireAudioFocus();
    }
  }

  void _push({bool force = false}) {
    final shouldHaveSession = shouldHaveMediaSession(
      inBackground: _inBackground,
      hasVideo: _ref.read(currentVideoProvider) != null,
      inPip: _ref.read(pipModeProvider),
    );
    // Relevant when a session exists/should-exist, or we're playing in the
    // foreground (audio focus is held there too). Otherwise nothing to do.
    if (!shouldHaveSession && !_sessionActive && !_playing) return;
    final second = _position.inSeconds;
    if (!force && second == _lastSentSecond) return;
    // In the foreground with no session there is nothing to keep updated.
    if (!shouldHaveSession && !_sessionActive) return;
    _lastSentSecond = second;
    if (shouldHaveSession && !_sessionActive) {
      _sessionActive = true;
    }
    final session = _ref.read(currentVideoProvider);
    _bridge.updateSession(
      title: session?.displayName ?? 'Kivo',
      mediaUri: session?.playbackPath ?? '',
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
    // A focus loss that interrupts a duck never gets its duckEnd — restore
    // the user's volume now or playback would resume stuck at 30%.
    _restoreDuckIfActive();
    if (_playing) _ref.read(playbackEngineProvider).pause();
    _pausedByFocus = false; // permanent: never auto-resume
  }

  void _onFocusTransientLoss() {
    _restoreDuckIfActive();
    if (_playing) {
      _ref.read(playbackEngineProvider).pause();
      _pausedByFocus = true;
    }
  }

  void _restoreDuckIfActive() {
    if (_ducking && !_duckUserAdjusted) {
      _ref.read(playbackEngineProvider).setVolume(_userPlayerVolume);
    }
    _ducking = false;
    _duckUserAdjusted = false;
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
    // Ducking — lower the volume but keep playing — only makes sense for
    // audio-only, music-player-style listening. For video, a quiet track loses
    // content just like a muted audiobook would, and a phone-call ring arrives
    // as a CAN_DUCK loss, so pause instead and auto-resume when focus returns.
    if (!_ref.read(audioOnlyProvider)) {
      _pausedByFocus = true;
      _ref.read(playbackEngineProvider).pause();
      return;
    }
    _ducking = true;
    _duckUserAdjusted = false;
    _ref.read(playbackEngineProvider).setVolume(_userPlayerVolume * 0.3);
  }

  void _onDuckEnd() {
    _restoreDuckIfActive();
    // A video paused for a duck (see _onDuckStart) resumes when the duck ends.
    if (_pausedByFocus) {
      _ref.read(playbackEngineProvider).play();
      _pausedByFocus = false;
    }
  }
}
