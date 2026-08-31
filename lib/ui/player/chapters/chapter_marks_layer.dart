import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/chapters/chapter.dart';
import '../../../player/chapters/chapters_provider.dart';
import '../../../player/engine/playback_provider.dart';

/// Chapter boundaries painted behind the seek bar's Slider, so the shape of a
/// long video is readable without opening anything.
///
/// Purely decorative — IgnorePointer, so scrubbing behaves exactly as before.
/// Draws nothing at all for the common file with no chapters.
class ChapterMarksLayer extends ConsumerWidget {
  const ChapterMarksLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(chaptersProvider);
    if (chapters.isEmpty) return const SizedBox.shrink();

    final total = ref.watch(durationProvider).value ?? Duration.zero;
    final marks = chapterMarks(chapters, total);
    if (marks.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('chapter-marks-paint'),
        painter: _ChapterMarksPainter(marks),
        size: Size.infinite,
      ),
    );
  }
}

class _ChapterMarksPainter extends CustomPainter {
  const _ChapterMarksPainter(this.marks);

  final List<double> marks;

  /// Matches the Slider's effective horizontal track inset, the same way
  /// AbRangeLayer does — the two must line up on the same track.
  static const _inset = 11.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    // Neutral rather than accent: the accent already means "played" on this
    // bar, and a boundary is not progress.
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (final frac in marks) {
      final x = _inset + frac * (size.width - 2 * _inset);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, cy), width: 2, height: 9),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ChapterMarksPainter old) => old.marks != marks;
}
