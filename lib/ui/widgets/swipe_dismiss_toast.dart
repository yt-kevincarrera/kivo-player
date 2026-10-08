import 'dart:async';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

/// The player's small bottom toast shell: dark capsule, animated in, hides by
/// itself after [autoHide], and can be swiped away in ANY direction — it
/// follows the finger, fades with distance, and either flies off along the
/// drag or springs back. The countdown pauses while a finger is on it and
/// starts over on release.
///
/// [onDismissed] fires exactly once, after the exit animation; the parent
/// then removes the toast. Give it a new key for new content, so a fresh
/// toast replays its entrance and gets a full countdown.
class SwipeDismissToast extends StatefulWidget {
  final Widget child;
  final Duration autoHide;
  final VoidCallback onDismissed;
  const SwipeDismissToast({
    super.key,
    required this.child,
    required this.autoHide,
    required this.onDismissed,
  });

  @override
  State<SwipeDismissToast> createState() => _SwipeDismissToastState();
}

class _SwipeDismissToastState extends State<SwipeDismissToast>
    with TickerProviderStateMixin {
  static const _dismissDistance = 56.0;
  static const _dismissVelocity = 600.0;
  static const _fadeDistance = 160.0;
  static const _flyDistance = 320.0;

  late final AnimationController _presence = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
  )..forward();
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  Offset _drag = Offset.zero;
  Offset _moveFrom = Offset.zero;
  Offset _moveTo = Offset.zero;
  Timer? _timer;
  bool _leaving = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _move.addListener(() {
      final t = Curves.easeOutCubic.transform(_move.value);
      setState(() => _drag = Offset.lerp(_moveFrom, _moveTo, t)!);
    });
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _presence.dispose();
    _move.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.autoHide, _hide);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDismissed();
  }

  /// Timed out: fade and drop a little.
  void _hide() {
    if (_leaving) return;
    _leaving = true;
    _presence.reverse().whenComplete(_finish);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_leaving) return;
    _move.stop();
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    if (_leaving) return;
    final v = d.velocity.pixelsPerSecond;
    if (_drag.distance > _dismissDistance || v.distance > _dismissVelocity) {
      _leaving = true;
      _timer?.cancel();
      final dir = _drag.distance > 0 ? _drag / _drag.distance : v / v.distance;
      final reduced = MediaQuery.disableAnimationsOf(context);
      _animateDrag(reduced ? _drag : dir * _flyDistance).whenComplete(_finish);
    } else {
      _animateDrag(Offset.zero);
      _startTimer();
    }
  }

  TickerFuture _animateDrag(Offset to) {
    _moveFrom = _drag;
    _moveTo = to;
    return _move.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_presence, _move]),
      builder: (context, child) {
        final p = Curves.easeOutCubic.transform(_presence.value);
        // In from 12 px below; out on timeout 8 px down.
        final rise = reduced
            ? 0.0
            : (_presence.status == AnimationStatus.reverse ? 8.0 : 12.0) *
                (1 - p);
        var fade = (1 - _drag.distance / _fadeDistance).clamp(0.0, 1.0);
        // Under reduced motion a dismissed toast stays put and fades.
        if (reduced && _leaving && _move.isAnimating) {
          fade *= 1 - _move.value;
        }
        return Opacity(
          opacity: (p * fade).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(_drag.dx, _drag.dy + rise),
            child: child,
          ),
        );
      },
      child: Listener(
        // Any finger on the toast (dragging it, or about to press its
        // action) holds the countdown; letting go starts it over.
        onPointerDown: (_) => _timer?.cancel(),
        onPointerUp: (_) {
          if (!_leaving) _startTimer();
        },
        onPointerCancel: (_) {
          if (!_leaving) _startTimer();
        },
        child: GestureDetector(
          // Count from the touch, not from where the drag was recognised —
          // otherwise the first ~36 px of a swipe would be lost.
          dragStartBehavior: DragStartBehavior.down,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onPanCancel: () {
            if (!_leaving) _animateDrag(Offset.zero);
          },
          child: Semantics(
            liveRegion: true,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(14),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
