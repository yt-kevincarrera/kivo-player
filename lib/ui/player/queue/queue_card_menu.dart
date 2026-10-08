import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';

enum QueueCardAction { playNext, remove }

/// The small menu a queue card opens when it is held and released in place:
/// a dark capsule just above the card ([anchor], global coordinates), or
/// below it when there is no room. Resolves to the chosen action, or null
/// when dismissed (tap outside, back).
Future<QueueCardAction?> showQueueCardMenu(
  BuildContext context, {
  required Rect anchor,
  required bool showPlayNext,
  required bool showRemove,
  required Color accent,
}) {
  return showGeneralDialog<QueueCardAction>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, _, _) => CustomSingleChildLayout(
      delegate: _AboveAnchor(anchor),
      child: _QueueCardMenu(
        showPlayNext: showPlayNext,
        showRemove: showRemove,
        accent: accent,
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      final reduced = MediaQuery.disableAnimationsOf(context);
      return FadeTransition(
        opacity: curved,
        child: reduced
            ? child
            : ScaleTransition(
                scale: Tween(begin: 0.94, end: 1.0).animate(curved),
                child: child,
              ),
      );
    },
  );
}

/// Centres the menu on the card, 8 px above it (below if it doesn't fit),
/// never closer than 8 px to a screen edge.
class _AboveAnchor extends SingleChildLayoutDelegate {
  final Rect anchor;
  const _AboveAnchor(this.anchor);
  static const _gap = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.all(_gap));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (anchor.center.dx - child.width / 2).clamp(
      _gap,
      size.width - child.width - _gap,
    );
    var y = anchor.top - child.height - _gap;
    if (y < _gap) y = anchor.bottom + _gap;
    return Offset(x, y.clamp(_gap, size.height - child.height - _gap));
  }

  @override
  bool shouldRelayout(_AboveAnchor old) => old.anchor != anchor;
}

class _QueueCardMenu extends StatelessWidget {
  final bool showPlayNext;
  final bool showRemove;
  final Color accent;
  const _QueueCardMenu({
    required this.showPlayNext,
    required this.showRemove,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget row(IconData icon, String label, QueueCardAction action) => InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).pop(action),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
        ),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showPlayNext)
                row(
                  Icons.queue_play_next_rounded,
                  l10n.playerQueuePlayNext,
                  QueueCardAction.playNext,
                ),
              if (showRemove)
                row(
                  Icons.remove_circle_outline_rounded,
                  l10n.playerQueueRemove,
                  QueueCardAction.remove,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
