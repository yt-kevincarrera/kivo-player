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
  });

  /// The creation timestamp in milliseconds, as a string. This is the
  /// playlist's identity, which is why two playlists may share a name.
  final String id;
  final String name;
  final int createdAtMs;
  final List<PlaylistEntry> entries;

  Playlist copyWith({String? name, List<PlaylistEntry>? entries}) => Playlist(
        id: id,
        name: name ?? this.name,
        createdAtMs: createdAtMs,
        entries: entries ?? this.entries,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'created': createdAtMs,
        'entries': entries.map((e) => e.toMap()).toList(),
      };

  factory Playlist.fromMap(Map m) => Playlist(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        createdAtMs: (m['created'] as num?)?.toInt() ?? 0,
        entries: ((m['entries'] as List?) ?? const [])
            .whereType<Map>()
            .map(PlaylistEntry.fromMap)
            .toList(),
      );
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
/// name. Callers pass the RAW media index: a video the user put in a playlist
/// by hand outranks the hidden-folders view filter.
List<ResolvedEntry> resolvePlaylist(Playlist playlist, List<VideoItem> index) {
  final byId = <String, VideoItem>{};
  final byName = <String, VideoItem>{};
  for (final v in index) {
    byId[v.id] = v;
    // First wins: two files can share a name in different folders, and the
    // earlier one is as good a guess as any when the id is already gone.
    byName.putIfAbsent(v.name, () => v);
  }

  return playlist.entries
      .map((e) => ResolvedEntry(e, byId[e.mediaId] ?? byName[e.displayName]))
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
