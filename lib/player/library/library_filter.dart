import '../../platform/interfaces/media_indexer.dart';
import '../queue/natural_sort.dart';

enum LibraryWatchFilter { all, unwatched, inProgress, completed }

enum LibrarySort {
  recent,
  nameAsc,
  nameDesc,
  durationAsc,
  durationDesc,
  sizeAsc,
  sizeDesc,
}

/// Maps a persisted `KivoSettings.librarySort` string (the enum's `.name`)
/// back to [LibrarySort], defaulting to [LibrarySort.recent] for anything
/// unrecognized (e.g. a future rollback reading an unknown value).
LibrarySort librarySortFor(String value) => LibrarySort.values.firstWhere(
  (s) => s.name == value,
  orElse: () => LibrarySort.recent,
);

/// The single source of truth for "what videos show, in what order" in the
/// Todo tab and in search results. Pure — no Riverpod, no widgets.
List<VideoItem> applyLibraryFilters(
  List<VideoItem> videos, {
  String query = '',
  LibrarySort sort = LibrarySort.recent,
  bool unwatchedOnly = false,
  Set<String> playedKeys = const {},
  LibraryWatchFilter watchFilter = LibraryWatchFilter.all,
  Set<String> inProgressKeys = const {},
  Set<String> completedKeys = const {},
}) {
  var out = videos;
  if (query.trim().isNotEmpty) {
    final q = query.trim().toLowerCase();
    out = out
        .where(
          (v) =>
              v.name.toLowerCase().contains(q) ||
              v.folder.toLowerCase().contains(q),
        )
        .toList();
  }
  bool isUnwatched(VideoItem v) => !playedKeys.contains(v.key) &&
      !inProgressKeys.contains(v.key) && !completedKeys.contains(v.key);
  if (unwatchedOnly) out = out.where(isUnwatched).toList();
  out = out
      .where(
        (v) => switch (watchFilter) {
          LibraryWatchFilter.all => true,
          LibraryWatchFilter.unwatched => isUnwatched(v),
          LibraryWatchFilter.inProgress => inProgressKeys.contains(v.key),
          LibraryWatchFilter.completed =>
            completedKeys.contains(v.key) && !inProgressKeys.contains(v.key),
        },
      )
      .toList();
  out = [...out];
  switch (sort) {
    case LibrarySort.recent:
      out.sort((a, b) => b.dateAddedMs.compareTo(a.dateAddedMs));
    case LibrarySort.nameAsc:
      out.sort((a, b) => naturalCompare(a.name, b.name));
    case LibrarySort.nameDesc:
      out.sort((a, b) => naturalCompare(b.name, a.name));
    case LibrarySort.durationAsc:
      out.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    case LibrarySort.durationDesc:
      out.sort((a, b) => b.durationMs.compareTo(a.durationMs));
    case LibrarySort.sizeAsc:
      out.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    case LibrarySort.sizeDesc:
      out.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  }
  return out;
}
