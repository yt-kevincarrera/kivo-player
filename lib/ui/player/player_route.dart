import 'package:flutter/material.dart';
import 'player_screen.dart';
import 'transition/grow_rect.dart';

/// Route for the player. It is deliberately **non-opaque** so the library
/// (the route beneath) keeps painting and shows through while the swipe-down
/// dismiss shrinks/fades the player — instead of a black void behind it.
///
/// On open, when [originRect] (the tapped tile's global rect) is given, the
/// player grows from that rect ([GrowFromRect]); otherwise (file-picker,
/// mini-player expand) it fades in. Every close fades — the close is carried by
/// the shrink-to-mini-player, so the route must not fly back to the tile.
Route<T> playerRoute<T>({Rect? originRect}) => PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => const PlayerScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // At rest: no wrappers, so the dismiss transforms in PlayerScreen are
        // undisturbed.
        if (animation.isCompleted) return child;
        if (originRect == null || animation.status == AnimationStatus.reverse) {
          return FadeTransition(opacity: animation, child: child);
        }
        return GrowFromRect(animation: animation, origin: originRect, child: child);
      },
    );
