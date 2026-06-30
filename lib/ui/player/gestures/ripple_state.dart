import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RippleEvent {
  final bool left;     // true = rewind side, false = forward side
  final int seconds;   // accumulated magnitude for this side/window
  final int id;        // monotonic — re-triggers the overlay even if left/seconds repeat
  const RippleEvent(this.left, this.seconds, this.id);
}

final rippleProvider = StateProvider<RippleEvent?>((ref) => null);

final rippleControllerProvider = Provider<RippleController>((ref) {
  final c = RippleController(ref);
  ref.onDispose(c.dispose);
  return c;
});

/// Accumulates rapid same-side double-taps (within [_window]) and publishes a
/// [RippleEvent] for the overlay. Mirrors SkipFeedback's accumulation, but
/// drives the on-screen ripple instead of the seek HUD chip.
class RippleController {
  RippleController(this._ref);
  final Ref _ref;
  static const _window = Duration(milliseconds: 1000);
  int _total = 0;
  int _dir = 0; // -1 left, 1 right, 0 idle
  int _id = 0;
  Timer? _timer;

  void bump({required bool left, required int seconds}) {
    final dir = left ? -1 : 1;
    if (dir == _dir && (_timer?.isActive ?? false)) {
      _total += seconds;
    } else {
      _total = seconds;
      _dir = dir;
    }
    _id++;
    _ref.read(rippleProvider.notifier).state = RippleEvent(left, _total, _id);
    _timer?.cancel();
    _timer = Timer(_window, () {
      _total = 0;
      _dir = 0;
    });
  }

  void dispose() => _timer?.cancel();
}
