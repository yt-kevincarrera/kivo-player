import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';

enum AbLoopPhase { armedA, armedB, active }

/// Immutable A-B loop snapshot. `null` provider state = no loop. [a] is set
/// from [AbLoopPhase.armedB] on; [a] and [b] are both set in
/// [AbLoopPhase.active].
class AbLoopState {
  final AbLoopPhase phase;
  final Duration? a;
  final Duration? b;
  const AbLoopState({required this.phase, this.a, this.b});
}

final abLoopProvider =
    NotifierProvider<AbLoopNotifier, AbLoopState?>(AbLoopNotifier.new);

class AbLoopNotifier extends Notifier<AbLoopState?> {
  static const minGap = Duration(seconds: 1);
  static const seekTolerance = Duration(seconds: 1);

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _jumpInFlight = false;

  @override
  AbLoopState? build() {
    ref.listen(positionProvider, (_, next) {
      final pos = next.value;
      if (pos == null) return;
      _position = pos;
      final s = state;
      if (s == null || s.phase != AbLoopPhase.active) return;
      if (pos >= s.b!) {
        // The loop's own jump goes straight to the engine — user seeks go
        // through PlayerController.seekTo, which is the cancel path. The
        // in-flight flag stops the ticks that arrive while the seek lands
        // (still ≥ B) from re-issuing the same jump.
        if (!_jumpInFlight) {
          _jumpInFlight = true;
          ref.read(playbackEngineProvider).seek(s.a!);
        }
      } else {
        _jumpInFlight = false;
      }
    });
    ref.listen(durationProvider, (_, next) {
      _duration = next.value ?? Duration.zero;
    });
    ref.listen(currentVideoProvider, (prev, next) {
      // The loop is a tool of the moment: it dies with its video.
      if (state != null && prev != next) state = null;
    });
    return null;
  }

  void begin() {
    _jumpInFlight = false;
    state = const AbLoopState(phase: AbLoopPhase.armedA);
  }

  void mark() {
    final s = state;
    if (s == null) return;
    switch (s.phase) {
      case AbLoopPhase.armedA:
        state = AbLoopState(phase: AbLoopPhase.armedB, a: _position);
      case AbLoopPhase.armedB:
        var a = s.a!;
        var b = _position;
        if (b < a) (a, b) = (b, a);
        if (b - a < minGap) return; // too tight — ignore this mark
        state = AbLoopState(phase: AbLoopPhase.active, a: a, b: b);
      case AbLoopPhase.active:
        cancel();
    }
  }

  void cancel() {
    _jumpInFlight = false;
    state = null;
  }

  /// Called from PlayerController.seekTo for every user-initiated seek.
  void userSeeked(Duration target) {
    final s = state;
    if (s == null || s.phase != AbLoopPhase.active) return;
    if (target < s.a! - seekTolerance || target > s.b! + seekTolerance) {
      cancel();
    }
  }

  void nudgeA(int seconds) {
    final s = state;
    if (s == null || s.phase != AbLoopPhase.active) return;
    var a = s.a! + Duration(seconds: seconds);
    final maxA = s.b! - minGap;
    if (a < Duration.zero) a = Duration.zero;
    if (a > maxA) a = maxA;
    state = AbLoopState(phase: AbLoopPhase.active, a: a, b: s.b);
    ref.read(playbackEngineProvider).seek(a); // hear the new start point
  }

  void nudgeB(int seconds) {
    final s = state;
    if (s == null || s.phase != AbLoopPhase.active) return;
    var b = s.b! + Duration(seconds: seconds);
    final minB = s.a! + minGap;
    if (b < minB) b = minB;
    if (_duration > Duration.zero && b > _duration) b = _duration;
    state = AbLoopState(phase: AbLoopPhase.active, a: s.a, b: b);
    // Seeking exactly to B would instantly trigger the jump — land 2s before
    // it (clamped to A) so the user hears the run-up into the loop point.
    var verify = b - const Duration(seconds: 2);
    if (verify < s.a!) verify = s.a!;
    ref.read(playbackEngineProvider).seek(verify);
  }
}
