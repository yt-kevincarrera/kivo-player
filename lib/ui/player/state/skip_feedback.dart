import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'hud_state.dart';

final skipFeedbackProvider = Provider<SkipFeedback>((ref) {
  final f = SkipFeedback(ref);
  ref.onDispose(f.dispose);
  return f;
});

/// Accumulates consecutive same-direction skips within [_window] and renders
/// the running total in the seek HUD. The actual seek (`skipBy`) is performed
/// by the caller; this only manages the cumulative display.
class SkipFeedback {
  SkipFeedback(this._ref);
  final Ref _ref;
  static const _window = Duration(milliseconds: 1000);
  int _total = 0;
  int _dir = 0;
  Timer? _timer;

  void bump(int seconds) {
    final dir = seconds.sign;
    if (dir == _dir && (_timer?.isActive ?? false)) {
      _total += seconds;
    } else {
      _total = seconds;
      _dir = dir;
    }
    final label = '${_total >= 0 ? '+' : '-'}${_total.abs()}s';
    _ref.read(hudProvider.notifier).show(HudKind.seek, _total >= 0 ? 1.0 : -1.0, label);
    _timer?.cancel();
    _timer = Timer(_window, () {
      _total = 0;
      _dir = 0;
    });
  }

  void dispose() => _timer?.cancel();
}
