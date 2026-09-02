import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/interfaces/media_indexer.dart';
import '../library/media_index.dart';
import '../library/played.dart';
import '../open/video_source.dart';
import 'playlist.dart';
import 'playlist_controller.dart';

/// The media index built into shared lookup maps once per index change,
/// instead of every playlist resolution rebuilding its own — see
/// [MediaLookup]'s doc.
///
/// Reads `mediaIndexProvider` — the RAW scan — rather than the
/// folder-filtered `libraryIndexProvider`. A video the user put in a playlist
/// by hand outranks a view filter: hiding its folder must not silently empty
/// the playlist. This is the only place in the app that reads past that
/// filter, and it is deliberate (mirrored by [resolvedPlaylistProvider]'s own
/// copy of this note, since that's the provider callers actually watch).
final mediaLookupProvider = Provider<MediaLookup>((ref) {
  final index = ref.watch(mediaIndexProvider).valueOrNull ?? const [];
  return MediaLookup.build(index);
});

/// One playlist's entries paired with the videos they point at.
///
/// `autoDispose`: nothing keeps a resolution alive once nobody is watching
/// it — a playlist screen closes, or `PlaylistPlayback` finishes the
/// transient `ref.read` it uses to start playback.
///
/// Watches `playlistsProvider` through `.select`, not the whole list: editing
/// playlist A rebuilds only playlist A's `Playlist` in the provider's state
/// (see `PlaylistsNotifier._update`), and `select` compares the selected
/// value with `==` before deciding whether to recompute — so playlist B's
/// resolution is untouched. That only works because [Playlist] now has
/// value equality (see its `==` there for why identity alone is not enough
/// once `HivePlaylistStore` is in play).
///
/// Reads `mediaIndexProvider` — the RAW scan — rather than the
/// folder-filtered `libraryIndexProvider`. A video the user put in a playlist
/// by hand outranks a view filter: hiding its folder must not silently empty
/// the playlist. This is the only place in the app that reads past that
/// filter, and it is deliberate.
final resolvedPlaylistProvider =
    Provider.autoDispose.family<List<ResolvedEntry>, String>((ref, playlistId) {
  final playlist = ref.watch(
    playlistsProvider.select((list) => _findPlaylist(list, playlistId)),
  );
  if (playlist == null) return const [];
  return resolvePlaylist(playlist, ref.watch(mediaLookupProvider));
});

Playlist? _findPlaylist(List<Playlist> playlists, String id) {
  for (final p in playlists) {
    if (p.id == id) return p;
  }
  return null;
}

/// Starts a playlist as the player's queue.
///
/// Builds nothing of its own: `openFromList` already turns a list of videos
/// into a full session — queue, names, ids, index — so the queue, autoplay,
/// the thumbnail strip and the media session all work unchanged.
class PlaylistPlayback {
  PlaylistPlayback(this._ref);
  final Ref _ref;

  /// Starts at the first unplayed entry. False when nothing is playable.
  bool play(String playlistId) {
    final resolved = _ref.read(resolvedPlaylistProvider(playlistId));
    final start = playlistStartIndex(resolved, _ref.read(playedKeysProvider));
    if (start < 0) return false;
    final opened = _open(resolved, start);
    // Only a play that actually opens something touches lastPlayedAtMs — a
    // refused play (nothing playable) must not count as "played".
    if (opened) _ref.read(playlistsProvider.notifier).touchLastPlayed(playlistId);
    return opened;
  }

  /// Starts at a specific entry. False when that entry is unavailable.
  bool playAt(String playlistId, int entryIndex) {
    final resolved = _ref.read(resolvedPlaylistProvider(playlistId));
    if (entryIndex < 0 || entryIndex >= resolved.length) return false;
    if (!resolved[entryIndex].available) return false;
    final opened = _open(resolved, entryIndex);
    if (opened) _ref.read(playlistsProvider.notifier).touchLastPlayed(playlistId);
    return opened;
  }

  bool _open(List<ResolvedEntry> resolved, int entryIndex) {
    // Unavailable entries cannot be queued, so the queue is the available
    // ones in playlist order — and the entry index has to be translated into
    // that shorter list.
    final available = <int, int>{}; // entry index -> queue index
    final videos = <VideoItem>[];
    for (var i = 0; i < resolved.length; i++) {
      final v = resolved[i].video;
      if (v == null) continue;
      available[i] = videos.length;
      videos.add(v);
    }
    final queueIndex = available[entryIndex];
    if (queueIndex == null || videos.isEmpty) return false;

    // Pin the position: a playlist may hold the same video twice, and
    // openFromList's URI search would resolve both to the first copy.
    _ref.read(currentVideoProvider.notifier).openFromList(
          videos[queueIndex],
          videos,
          at: queueIndex,
        );
    return true;
  }
}

final playlistPlaybackProvider =
    Provider<PlaylistPlayback>((ref) => PlaylistPlayback(ref));
