import 'dart:async';

/// One physical key hold, independent of an OEM remote's repeat frequency.
/// Pending targets accumulate even while a slow decoder hasn't reported its
/// last seek. Release, focus loss and app suspension must call [stop].
class RemoteSeek {
  RemoteSeek({
    required this.position,
    required this.duration,
    required this.onSeek,
  });
  final Duration Function() position;
  final Duration Function() duration;
  final void Function(Duration target, int deltaSeconds) onSeek;
  Timer? _delay;
  Timer? _repeat;
  int _heldMilliseconds = 0;
  Duration _target = Duration.zero;
  int? direction;
  int _step = 3;
  bool _progressive = true;

  void start(int direction, {required int seconds, required bool progressive}) {
    if (this.direction == direction) return;
    stop();
    this.direction = direction.sign;
    _step = seconds.clamp(1, 60);
    _progressive = progressive;
    _target = position();
    _seek();
    _delay = Timer(const Duration(milliseconds: 450), () {
      _heldMilliseconds = 450;
      _seek();
      _repeat = Timer.periodic(const Duration(milliseconds: 200), (_) {
        _heldMilliseconds += 200;
        _seek();
      });
    });
  }

  void _seek() {
    final total = duration();
    if (direction == null || total <= Duration.zero) return;
    final held = _heldMilliseconds;
    final multiplier = !_progressive
        ? 1
        : held >= 4000
        ? 10
        : held >= 2000
        ? 3
        : 1;
    final wanted = _target + Duration(seconds: direction! * _step * multiplier);
    final next = Duration(
      milliseconds: wanted.inMilliseconds.clamp(0, total.inMilliseconds),
    );
    final delta = (next - _target).inSeconds;
    _target = next;
    if (delta != 0) onSeek(next, delta);
  }

  void stop() {
    _delay?.cancel();
    _repeat?.cancel();
    _delay = null;
    _repeat = null;
    direction = null;
    _heldMilliseconds = 0;
  }
}
