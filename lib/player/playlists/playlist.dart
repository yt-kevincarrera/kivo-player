import '../../platform/interfaces/media_indexer.dart';

/// One video's place in a playlist.
///
/// Both identities are stored on purpose. [mediaId] survives a rename — the
/// app renames through MediaStore, which keeps the row — but not a move, which
/// usually creates a new row. [displayName] survives a move but not a rename.
/// Keeping both means an entry only breaks if both change at once.
class PlaylistEntry {
  const PlaylistEntry({required this.mediaId, required this.displayName});

  final String mediaId;
  final String displayName;

  Map<String, dynamic> toMap() => {'i': mediaId, 'n': displayName};

  factory PlaylistEntry.fromMap(Map m) => PlaylistEntry(
        mediaId: (m['i'] as String?) ?? '',
        displayName: (m['n'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is PlaylistEntry &&
      other.mediaId == mediaId &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(mediaId, displayName);
}

/// A hand-made, ordered list of videos. The order of [entries] IS the playlist.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAtMs,
    required this.entries,
    this.lastPlayedAtMs = 0,
  });

  /// The creation timestamp in milliseconds, as a string. This is the
  /// playlist's identity, which is why two playlists may share a name.
  final String id;
  final String name;
  final int createdAtMs;
  final List<PlaylistEntry> entries;

  /// When this playlist last actually opened something, in epoch ms — 0 if
  /// never. Set only by [PlaylistsNotifier.touchLastPlayed], which
  /// `PlaylistPlayback.play`/`playAt` call after a play actually starts (not
  /// on a refused play). Drives `PlaylistSort.lastPlayed`.
  final int lastPlayedAtMs;

  Playlist copyWith({
    String? name,
    List<PlaylistEntry>? entries,
    int? lastPlayedAtMs,
  }) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        createdAtMs: createdAtMs,
        entries: entries ?? this.entries,
        lastPlayedAtMs: lastPlayedAtMs ?? this.lastPlayedAtMs,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'created': createdAtMs,
        'entries': entries.map((e) => e.toMap()).toList(),
        'lp': lastPlayedAtMs,
      };

  factory Playlist.fromMap(Map m) => Playlist(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        createdAtMs: (m['created'] as num?)?.toInt() ?? 0,
        entries: ((m['entries'] as List?) ?? const [])
            .whereType<Map>()
            .map(PlaylistEntry.fromMap)
            .toList(),
        // Absent on a playlist stored before this field existed — reads as
        // "never played", which is correct rather than merely harmless.
        lastPlayedAtMs: (m['lp'] as num?)?.toInt() ?? 0,
      );

  // Value equality, entries included, so `playlistsProvider.select` (see
  // playlist_playback.dart) can tell "this one playlist's content is
  // unchanged" from "a sibling playlist changed and the list was rebuilt"
  // without it, `select` would compare object identity, which
  // HivePlaylistStore.all() breaks on every read — it deserializes a fresh
  // Playlist for every row, touched or not, so an untouched playlist would
  // look "new" every time and select would never filter anything out. No
  // package:collection for the entries comparison, same call as
  // PlaylistEntry's own == above: one list-equality check isn't worth adding
  // the dependency for.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Playlist) return false;
    if (other.id != id ||
        other.name != name ||
        other.createdAtMs != createdAtMs ||
        other.lastPlayedAtMs != lastPlayedAtMs) {
      return false;
    }
    if (other.entries.length != entries.length) return false;
    for (var i = 0; i < entries.length; i++) {
      if (other.entries[i] != entries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, createdAtMs, lastPlayedAtMs, Object.hashAll(entries));
}

/// The media index built into O(1) lookup maps once and shared by every
/// playlist's resolution, instead of every `resolvePlaylist` call rebuilding
/// both maps over the whole index. See `mediaLookupProvider` in
/// playlist_playback.dart for where this gets built and shared.
class MediaLookup {
  const MediaLookup({required this.byId, required this.byName});

  final Map<String, VideoItem> byId;
  final Map<String, VideoItem> byName;

  factory MediaLookup.build(List<VideoItem> index) {
    final byId = <String, VideoItem>{};
    final byName = <String, VideoItem>{};
    for (final v in index) {
      byId[v.id] = v;
      // First wins: two files can share a name in different folders, and the
      // earlier one is as good a guess as any when the id is already gone.
      byName.putIfAbsent(v.name, () => v);
    }
    return MediaLookup(byId: byId, byName: byName);
  }

  /// Matches by [PlaylistEntry.mediaId] first and falls back to the display
  /// name — same order resolvePlaylist has always used.
  VideoItem? resolve(PlaylistEntry entry) =>
      byId[entry.mediaId] ?? byName[entry.displayName];
}

/// An entry paired with the video it points at, or null when that video is
/// not on the device right now.
class ResolvedEntry {
  const ResolvedEntry(this.entry, this.video);

  final PlaylistEntry entry;
  final VideoItem? video;

  bool get available => video != null;
}

/// Pairs each entry with its video, in playlist order.
///
/// Matches by [PlaylistEntry.mediaId] first and falls back to the display
/// name. Callers pass a [MediaLookup] built from the RAW media index: a video
/// the user put in a playlist by hand outranks the hidden-folders view
/// filter. Pure and Riverpod-free — [lookup] is built once by the caller
/// (see `mediaLookupProvider`) and shared across every playlist's resolution
/// rather than rebuilt here on every call.
List<ResolvedEntry> resolvePlaylist(Playlist playlist, MediaLookup lookup) {
  return playlist.entries
      .map((e) => ResolvedEntry(e, lookup.resolve(e)))
      .toList();
}

/// Index of the entry a "play" should start on, or -1 when nothing is playable.
///
/// The first available entry that has not been played, so a series continues
/// where it was left. Falls back to the top once everything is played —
/// otherwise a finished series could not be replayed without scrolling.
///
/// Derived rather than stored: [PlayedStore] already knows what is finished,
/// so there is no second copy of the truth to drift.
int playlistStartIndex(List<ResolvedEntry> resolved, Set<String> playedNames) {
  var firstAvailable = -1;
  for (var i = 0; i < resolved.length; i++) {
    if (!resolved[i].available) continue;
    if (firstAvailable < 0) firstAvailable = i;
    if (!playedNames.contains(resolved[i].video!.name)) return i;
  }
  return firstAvailable;
}
