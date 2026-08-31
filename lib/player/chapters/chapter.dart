/// A named point in the video's own timeline.
///
/// Chapters are metadata, not structure: a file with chapters is still one
/// continuous video that plays start to finish exactly as it would without
/// them. They only add ways to navigate it.
class MediaChapter {
  const MediaChapter({required this.title, required this.start});

  final String title;
  final Duration start;

  @override
  bool operator ==(Object other) =>
      other is MediaChapter && other.title == title && other.start == start;

  @override
  int get hashCode => Object.hash(title, start);
}

/// How close to a chapter's start counts as "just entered it" for [previousChapterStart].
const _restartWindow = Duration(seconds: 3);

/// Index of the chapter [position] falls in, or -1.
///
/// -1 covers both an empty list and a position before the first chapter starts
/// — some files leave a gap at the front, and pretending that gap belongs to
/// chapter 0 would mislabel it in the UI.
int currentChapterIndex(List<MediaChapter> chapters, Duration position) {
  var found = -1;
  for (var i = 0; i < chapters.length; i++) {
    if (chapters[i].start <= position) {
      found = i;
    } else {
      break; // chapters are in order, so the first later one ends the search
    }
  }
  return found;
}

/// Where a skip-forward lands, or null in the last chapter.
Duration? nextChapterStart(List<MediaChapter> chapters, Duration position) {
  for (final c in chapters) {
    if (c.start > position) return c.start;
  }
  return null;
}

/// Where a skip-back lands, or null when there is nowhere further back.
///
/// Restarts the chapter you are in, unless you only just entered it, in which
/// case it goes to the one before — the behaviour every music player's
/// back button has, so nobody has to learn it.
Duration? previousChapterStart(List<MediaChapter> chapters, Duration position) {
  final index = currentChapterIndex(chapters, position);
  if (index < 0) return null;

  final justEntered = position - chapters[index].start < _restartWindow;
  if (!justEntered) return chapters[index].start;
  return index > 0 ? chapters[index - 1].start : null;
}

/// Chapter starts as fractions of [total], for drawing marks on the seek bar.
///
/// A chapter starting at zero produces no mark: the bar already begins there
/// and a tick on the very edge reads as a rendering glitch. Anything at or
/// past the end is dropped rather than drawn off the bar — some files carry a
/// trailing chapter at exactly the duration.
List<double> chapterMarks(List<MediaChapter> chapters, Duration total) {
  if (total <= Duration.zero) return const [];
  final out = <double>[];
  for (final c in chapters) {
    if (c.start <= Duration.zero || c.start >= total) continue;
    out.add(c.start.inMilliseconds / total.inMilliseconds);
  }
  return out;
}
