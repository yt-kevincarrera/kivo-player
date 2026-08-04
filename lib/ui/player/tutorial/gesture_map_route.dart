import 'package:flutter/material.dart';
import 'gesture_map_page.dart';

/// Route for the gesture map. **Non-opaque** so the paused video (or the
/// settings screen, when reopened from there) keeps painting behind the scrim.
///
/// It is a route and not another entry in PlayerScreen's overlay Stack on
/// purpose: the back button then pops only the map — the player's PopScope
/// (which minimizes to the mini-bar) never sees it — and the exact same screen
/// works with no player underneath.
Route<void> gestureMapRoute() => PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => const GestureMapScreen(),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
