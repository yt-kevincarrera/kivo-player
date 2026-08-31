import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/interfaces/media_indexer.dart';
import '../library/media_index.dart';
import '../library/played.dart';
import '../open/video_source.dart';
import 'playlist.dart';
import 'playlist_controller.dart';

/// One playlist's entries paired with the videos they point at.
///
/// Reads `mediaIndexProvider` — the RAW scan — rather than the folder-filtered
/// `libraryIndexProvider`. A video the user put in a playlist by hand outranks
/// a view filter: hiding its folder must not silently empty the playlist. This
/// is the only place in the app that reads past that filter, and it is
/// deliberate.
final resolvedPlaylistProvider =
    Provider.family<List<ResolvedEntry>, String>((ref, playlistId) {
  final playlists = ref.watch(playlistsProvider);
  final index = ref.watch(mediaIndexProvider).valueOrNull ?? const [];
  for (final p in playlists) {
    if (p.id == playlistId) return resolvePlaylist(p, index);
  }
  return const [];
});

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
    return _open(resolved, start);
  }

  /// Starts at a specific entry. False when that entry is unavailable.
  bool playAt(String playlistId, int entryIndex) {
    final resolved = _ref.read(resolvedPlaylistProvider(playlistId));
    if (entryIndex < 0 || entryIndex >= resolved.length) return false;
    if (!resolved[entryIndex].available) return false;
    return _open(resolved, entryIndex);
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
