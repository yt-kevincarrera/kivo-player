import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'playlist.dart';

abstract class PlaylistStore {
  /// Newest first — the list people are most likely to want is the one they
  /// just made.
  List<Playlist> all();
  Future<void> put(Playlist playlist);
  Future<void> remove(String id);
}

/// One Hive key per playlist rather than one list under a single key: editing
/// one playlist then rewrites only that playlist, which matters because a
/// drag-to-reorder writes on every frame of the drag's settle.
class HivePlaylistStore implements PlaylistStore {
  HivePlaylistStore(this.box);
  final Box box;

  @override
  List<Playlist> all() {
    final out = <Playlist>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) out.add(Playlist.fromMap(raw));
    }
    out.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return out;
  }

  @override
  Future<void> put(Playlist playlist) =>
      box.put(playlist.id, playlist.toMap());

  @override
  Future<void> remove(String id) => box.delete(id);
}

/// Session-only store: a valid fallback and what the tests use.
class InMemoryPlaylistStore implements PlaylistStore {
  final Map<String, Playlist> _data = {};

  @override
  List<Playlist> all() {
    final out = _data.values.toList();
    out.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return out;
  }

  @override
  Future<void> put(Playlist playlist) async => _data[playlist.id] = playlist;

  @override
  Future<void> remove(String id) async => _data.remove(id);
}

final playlistStoreProvider =
    Provider<PlaylistStore>((ref) => InMemoryPlaylistStore());
