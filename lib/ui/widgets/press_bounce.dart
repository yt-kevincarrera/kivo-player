import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// PressBounce — translucent Listener that scales its child to 0.92 on press.
// Extracted from center_controls.dart so it can be shared across widgets.
// ---------------------------------------------------------------------------

class PressBounce extends StatefulWidget {
  final Widget child;
  const PressBounce({super.key, required this.child});
  @override
  State<PressBounce> createState() => _PressBounceState();
}

class _PressBounceState extends State<PressBounce> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
        // Translucent so the widget beneath still gets the tap; we only
        // observe the press to drive the scale (no event consumed).
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
