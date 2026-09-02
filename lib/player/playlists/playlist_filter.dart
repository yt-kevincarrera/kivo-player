import 'playlist.dart';

enum PlaylistSort { recent, nameAsc, nameDesc, mostVideos, lastPlayed }

/// Maps a persisted `KivoSettings.playlistSort` string (the enum's `.name`)
/// back to [PlaylistSort], defaulting to [PlaylistSort.recent] for anything
/// unrecognized (e.g. a future rollback reading an unknown value). Mirrors
/// `librarySortFor` in lib/player/library/library_filter.dart.
PlaylistSort playlistSortFor(String value) => PlaylistSort.values.firstWhere(
      (s) => s.name == value,
      orElse: () => PlaylistSort.recent,
    );

/// The single source of truth for "which lists show, in what order" in the
/// Listas tab. Pure — no Riverpod, no widgets. Mirrors
/// `applyLibraryFilters` in lib/player/library/library_filter.dart.
///
/// [query] matches case-insensitively (plain `toLowerCase()` — this repo has
/// no accent-folding helper today; `applyLibraryFilters` does the same
/// plain-ASCII-fold, so this stays consistent with it rather than inventing
/// a new normalisation the rest of search doesn't have) against the
/// playlist's own name first, and — so "which list did I put episode 4 in?"
/// is answerable — against any entry's `displayName` as a second criterion.
List<Playlist> applyPlaylistFilters(
  List<Playlist> all, {
  required String query,
  required PlaylistSort sort,
}) {
  var out = all;
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    out = out
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.entries.any((e) => e.displayName.toLowerCase().contains(q)))
        .toList();
  }
  out = [...out];
  // Every branch below breaks ties explicitly (never left to List.sort's
  // stability, which Dart does not guarantee) so ordering is deterministic
  // regardless of the input list's own order.
  switch (sort) {
    case PlaylistSort.recent:
      out.sort(_byRecent);
    case PlaylistSort.nameAsc:
      out.sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : _byRecent(a, b);
      });
    case PlaylistSort.nameDesc:
      out.sort((a, b) {
        final byName = b.name.toLowerCase().compareTo(a.name.toLowerCase());
        return byName != 0 ? byName : _byRecent(a, b);
      });
    case PlaylistSort.mostVideos:
      out.sort((a, b) {
        final byCount = b.entries.length.compareTo(a.entries.length);
        return byCount != 0 ? byCount : _byRecent(a, b);
      });
    case PlaylistSort.lastPlayed:
      out.sort(_byLastPlayed);
  }
  return out;
}

/// Newest-created first; ties (e.g. two playlists made in the same
/// millisecond) broken by id — `Playlist.id` is the creation timestamp as a
/// string, so this is just a second look at the same clock, deterministic
/// either way.
int _byRecent(Playlist a, Playlist b) {
  final byCreated = b.createdAtMs.compareTo(a.createdAtMs);
  return byCreated != 0 ? byCreated : b.id.compareTo(a.id);
}

/// Never-played (`lastPlayedAtMs == 0`) sorts LAST, after every playlist that
/// has actually been opened at least once, most-recently-played first among
/// those. Within either group, falls back to [_byRecent] so the result is
/// still fully deterministic.
int _byLastPlayed(Playlist a, Playlist b) {
  final aPlayed = a.lastPlayedAtMs > 0;
  final bPlayed = b.lastPlayedAtMs > 0;
  if (aPlayed != bPlayed) return aPlayed ? -1 : 1;
  if (!aPlayed) return _byRecent(a, b);
  final byLastPlayed = b.lastPlayedAtMs.compareTo(a.lastPlayedAtMs);
  return byLastPlayed != 0 ? byLastPlayed : _byRecent(a, b);
}
