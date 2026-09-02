/// A user-made point in a video's own timeline.
///
/// Unlike a chapter — metadata baked into the file — a bookmark is made by
/// the person watching, to come back to something later. It lives only in
/// this app's storage, keyed to the video's file name (see [BookmarkStore]),
/// and has no effect on playback until it is tapped.
class Bookmark {
  const Bookmark({
    required this.positionMs,
    required this.name,
    required this.createdAtMs,
  });

  final int positionMs;

  /// Empty until the user names it — the row then falls back to showing the
  /// time instead.
  final String name;
  final int createdAtMs;

  Bookmark copyWith({String? name}) => Bookmark(
        positionMs: positionMs,
        name: name ?? this.name,
        createdAtMs: createdAtMs,
      );

  Map<String, dynamic> toMap() => {'p': positionMs, 'n': name, 'c': createdAtMs};

  // Short keys, tolerant of missing/unknown keys and of the Map<dynamic,dynamic>
  // Hive hands back on read — matches Playlist.fromMap.
  factory Bookmark.fromMap(Map m) => Bookmark(
        positionMs: (m['p'] as num?)?.toInt() ?? 0,
        name: (m['n'] as String?) ?? '',
        createdAtMs: (m['c'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is Bookmark &&
      other.positionMs == positionMs &&
      other.name == name &&
      other.createdAtMs == createdAtMs;

  @override
  int get hashCode => Object.hash(positionMs, name, createdAtMs);
}

/// Bookmark positions as fractions of [total], for drawing marks on the seek bar.
///
/// Mirrors [chapterMarks]: nothing at or before zero and nothing at or past
/// the end draws a mark — a tick glued to either edge of the bar reads as a
/// rendering glitch, not a mark.
List<double> bookmarkMarks(List<Bookmark> bookmarks, Duration total) {
  if (total <= Duration.zero) return const [];
  final out = <double>[];
  for (final b in bookmarks) {
    if (b.positionMs <= 0 || b.positionMs >= total.inMilliseconds) continue;
    out.add(b.positionMs / total.inMilliseconds);
  }
  return out;
}
