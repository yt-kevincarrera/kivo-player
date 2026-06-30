import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// PressBounce — two modes depending on whether onTap is provided.
//
// PULSE mode  (onTap != null): wraps the child in a GestureDetector. On a
//   confirmed tap it plays a quick scale pulse (1.0 → 1.04 → 1.0) and calls
//   onTap. Because the pulse is driven by the confirmed onTap callback (not
//   onPointerDown), it never fires while scrolling.
//
// LEGACY mode (onTap == null): keeps the original translucent Listener +
//   AnimatedScale(0.92) press-hold behavior. This is used by the player's
//   center controls, which must stay untouched.
// ---------------------------------------------------------------------------

class PressBounce extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  const PressBounce({super.key, this.onTap, required this.child});
  @override
  State<PressBounce> createState() => _PressBounceState();
}

class _PressBounceState extends State<PressBounce>
    with SingleTickerProviderStateMixin {
  // Pulse controller — always created; only used in pulse mode.
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  // Legacy mode state
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _pulse = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.04).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.04, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0);
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap != null) {
      // Pulse mode: confirmed-tap, never fires on scroll.
      return GestureDetector(
        onTap: _handleTap,
        child: ScaleTransition(scale: _pulse, child: widget.child),
      );
    }

    // Legacy mode: translucent Listener + AnimatedScale for the player.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
