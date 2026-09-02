import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../player/bookmarks/bookmark.dart';
import '../../../player/bookmarks/bookmarks_provider.dart';
import '../../../player/engine/playback_provider.dart';

/// Bookmark positions painted behind the seek bar's Slider, alongside
/// [ChapterMarksLayer] — same track, same inset, but a small accent-coloured
/// diamond instead of the chapter tick, so the two read apart.
///
/// Purely decorative — IgnorePointer, so scrubbing behaves exactly as before.
/// Draws nothing for the common case of a video with no bookmarks.
class BookmarkMarksLayer extends ConsumerWidget {
  const BookmarkMarksLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider);
    if (bookmarks.isEmpty) return const SizedBox.shrink();

    final total = ref.watch(durationProvider).value ?? Duration.zero;
    final marks = bookmarkMarks(bookmarks, total);
    if (marks.isEmpty) return const SizedBox.shrink();

    final accent = Color(ref.watch(settingsProvider).accentColor);

    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('bookmark-marks-paint'),
        painter: _BookmarkMarksPainter(marks, accent),
        size: Size.infinite,
      ),
    );
  }
}

class _BookmarkMarksPainter extends CustomPainter {
  const _BookmarkMarksPainter(this.marks, this.color);

  final List<double> marks;
  final Color color;

  /// Matches ChapterMarksLayer's and AbRangeLayer's inset — all three layers
  /// must line up on the same track.
  static const _inset = 11.0;
  static const _radius = 4.5;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final paint = Paint()..color = color;
    for (final frac in marks) {
      final x = _inset + frac * (size.width - 2 * _inset);
      final path = Path()
        ..moveTo(x, cy - _radius)
        ..lineTo(x + _radius, cy)
        ..lineTo(x, cy + _radius)
        ..lineTo(x - _radius, cy)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_BookmarkMarksPainter old) =>
      !listEquals(old.marks, marks) || old.color != color;
}
