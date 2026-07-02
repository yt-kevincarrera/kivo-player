import 'package:flutter/material.dart';
import 'player_screen.dart';

/// Route for the player. It is deliberately **non-opaque** so the library
/// (the route beneath) keeps painting and shows through while the swipe-down
/// dismiss shrinks/fades the player — instead of a black void behind it.
///
/// The visible motion is carried by the Hero (open) and the dismiss drag
/// (close); the route's own fade is short and low so it adds "nothing extra".
Route<T> playerRoute<T>() => PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => const PlayerScreen(),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
