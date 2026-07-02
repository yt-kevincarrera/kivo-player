import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../control/gesture_math.dart';
import '../control/player_controller.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';

enum SleepTimerMode { fixed, episode }

/// Immutable snapshot of the running sleep timer. `null` provider state means
/// no timer. [cycle] increments on every (re)start so the warning toast can
/// tell a fresh warning window from one the user already dismissed with ✕.
class SleepTimerState {
  final SleepTimerMode mode;
  final Duration original;
  final Duration remaining;
  final bool warning;
  final int cycle;
  const SleepTimerState({
    required this.mode,
    required this.original,
    required this.remaining,
    required this.warning,
    required this.cycle,
  });

  SleepTimerState copyWith({Duration? remaining, bool? warning}) => SleepTimerState(
        mode: mode,
        original: original,
        remaining: remaining ?? this.remaining,
        warning: warning ?? this.warning,
        cycle: cycle,
      );
}

/// Injectable clock so tests can control wall-time.
final sleepClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState?>(SleepTimerNotifier.new);

class SleepTimerNotifier extends Notifier<SleepTimerState?> {
  static const warningWindow = Duration(seconds: 10);
  static const _tickEvery = Duration(milliseconds: 250);

  Timer? _ticker;
  DateTime? _endsAt; // fixed mode only
  int _cycle = 0;

  Duration? _duration;        // last known video duration
  Duration? _episodeBaseline; // remaining when episode mode engaged (meter 100%)

  // Fade bookkeeping. The fade multiplies the player volume the user actually
  // has (mapped through volumeMapping, system volume untouched); a manual
  // volume change mid-fade cancels the fade silently — clear awake signal.
  bool _fading = false;
  bool _fadeCancelled = false;
  double _fadeBase = 100;

  @override
  SleepTimerState? build() {
    ref.listen(volumePercentProvider, (prev, next) {
      if (_fading) _fadeCancelled = true;
    });
    ref.listen(positionProvider, (prev, next) {
      final pos = next.value;
      if (pos != null) _onPosition(pos);
    });
    ref.listen(durationProvider, (prev, next) {
      final dur = next.value;
      if (dur != null) _duration = dur;
    });
    ref.listen(currentVideoProvider, (prev, next) {
      // New video while episode mode is active: re-apply to the new video —
      // reset the warning/fade so the countdown restarts from its length.
      if (state?.mode == SleepTimerMode.episode && prev != next) {
        _stopFadeAndRestore();
        _duration = null;
        _episodeBaseline = null;
        state = state!.copyWith(remaining: Duration.zero, warning: false);
      }
    });
    ref.onDispose(() => _ticker?.cancel());
    return null;
  }

  DateTime get _now => ref.read(sleepClockProvider)();

  double get _userPlayerVolume {
    final boost = ref.read(settingsProvider).volumeBoostMax.toDouble();
    return volumeMapping(ref.read(volumePercentProvider), boost).playerPercent;
  }

  void startFixed(Duration d) {
    _endsAt = _now.add(d);
    // Restore-then-reset: extending from inside the warning window must undo
    // the partially-applied fade immediately.
    _stopFadeAndRestore();
    _cycle++;
    state = SleepTimerState(
      mode: SleepTimerMode.fixed,
      original: d,
      remaining: d,
      warning: false,
      cycle: _cycle,
    );
    _startTicker();
  }

  void startEpisode() {
    _endsAt = null;
    _episodeBaseline = null;
    _stopFadeAndRestore();
    _cycle++;
    state = SleepTimerState(
      mode: SleepTimerMode.episode,
      original: Duration.zero,
      remaining: Duration.zero,
      warning: false,
      cycle: _cycle,
    );
  }

  void extend() {
    final s = state;
    if (s == null) return;
    if (s.mode == SleepTimerMode.fixed) {
      startFixed(s.original);
    } else {
      cancel();
    }
  }

  void cancel() {
    _stopFadeAndRestore();
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    _episodeBaseline = null;
    state = null;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickEvery, (_) => _tick());
  }

  void _tick() {
    final s = state;
    final endsAt = _endsAt;
    if (s == null || endsAt == null) return;
    final remaining = endsAt.difference(_now);
    if (remaining <= Duration.zero) {
      _fire();
      return;
    }
    final warning = remaining <= warningWindow;
    if (warning) _applyFade(remaining);
    // Only emit when something visible changed (second boundary or flag flip)
    // to avoid 4 rebuilds per second.
    if (warning != s.warning || remaining.inSeconds != s.remaining.inSeconds) {
      state = s.copyWith(remaining: remaining, warning: warning);
    }
  }

  void _fire() {
    final engine = ref.read(playbackEngineProvider);
    engine.pause();
    _stopFadeAndRestore();
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    state = null;
  }

  void _onPosition(Duration pos) {
    final s = state;
    final dur = _duration;
    if (s == null || s.mode != SleepTimerMode.episode || dur == null || dur == Duration.zero) {
      return;
    }
    final remaining = dur - pos;
    if (remaining <= const Duration(milliseconds: 300)) {
      // Video reached its natural end. pause() is a safety belt — with no
      // autoplay the engine stops on the last frame anyway.
      _fire();
      return;
    }
    _episodeBaseline ??= remaining;
    final warning = remaining <= warningWindow;
    if (warning) _applyFade(remaining);
    if (warning != s.warning || remaining.inSeconds != s.remaining.inSeconds) {
      state = SleepTimerState(
        mode: SleepTimerMode.episode,
        original: _episodeBaseline!,
        remaining: remaining,
        warning: warning,
        cycle: s.cycle,
      );
    }
  }

  void _applyFade(Duration remaining) {
    if (_fadeCancelled) return;
    if (!_fading) {
      _fading = true;
      _fadeBase = _userPlayerVolume;
    }
    final factor =
        (remaining.inMilliseconds / warningWindow.inMilliseconds).clamp(0.0, 1.0);
    ref.read(playbackEngineProvider).setVolume(_fadeBase * factor);
  }

  void _stopFadeAndRestore() {
    if (_fading && !_fadeCancelled) {
      ref.read(playbackEngineProvider).setVolume(_userPlayerVolume);
    }
    _resetFade();
  }

  void _resetFade() {
    _fading = false;
    _fadeCancelled = false;
  }
}
