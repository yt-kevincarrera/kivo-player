import 'package:flutter/material.dart';

/// Kivo's watched-progress meter: [segments] discrete blocks, the first
/// `fraction` of them lit in [accent] — the segmented motif of the player's
/// HUDs, used under library thumbnails and the queue strip's cards.
class SegmentedProgress extends StatelessWidget {
  final double fraction;
  final Color accent;
  final Color unlit;
  final int segments;
  final double height;
  const SegmentedProgress(
    this.fraction, {
    super.key,
    required this.accent,
    required this.unlit,
    this.segments = 16,
    this.height = 4,
  });

  @override
  Widget build(BuildContext context) {
    final lit = (fraction * segments).round();
    return Row(
      children: [
        for (var i = 0; i < segments; i++)
          Expanded(
            child: Container(
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 0.5),
              color: i < lit ? accent : unlit,
            ),
          ),
      ],
    );
  }
}
