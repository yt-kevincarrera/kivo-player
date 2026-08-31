import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/interfaces/media_indexer.dart';
import 'playlist.dart';
import 'playlist_store.dart';

/// Injected so playlist ids are deterministic under test. Ids are creation
/// timestamps, so without this every test would produce a different one.
final playlistClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Every playlist, newest first. The single writer for the store.
class PlaylistsNotifier extends Notifier<List<Playlist>> {
  PlaylistStore get _store => ref.read(playlistStoreProvider);

  @override
  List<Playlist> build() => _store.all();

  Future<Playlist> create(String name) async {
    final now = ref.read(playlistClockProvider)();
    final playlist = Playlist(
      id: '${now.millisecondsSinceEpoch}',
      name: name,
      createdAtMs: now.millisecondsSinceEpoch,
      entries: const [],
    );
    await _store.put(playlist);
    state = _store.all();
    return playlist;
  }

  Future<void> delete(String id) async {
    await _store.remove(id);
    state = _store.all();
  }

  Future<void> rename(String id, String name) =>
      _update(id, (p) => p.copyWith(name: name));

  Future<void> addVideos(String id, List<VideoItem> videos) => _update(
        id,
        (p) => p.copyWith(entries: [
          ...p.entries,
          for (final v in videos)
            PlaylistEntry(mediaId: v.id, displayName: v.name),
        ]),
      );

  Future<void> removeEntryAt(String id, int index) => _update(id, (p) {
        if (index < 0 || index >= p.entries.length) return p;
        final entries = [...p.entries]..removeAt(index);
        return p.copyWith(entries: entries);
      });

  Future<void> reorder(String id, int oldIndex, int newIndex) => _update(id, (p) {
        if (oldIndex < 0 || oldIndex >= p.entries.length) return p;
        final entries = [...p.entries];
        final moved = entries.removeAt(oldIndex);
        entries.insert(newIndex.clamp(0, entries.length), moved);
        return p.copyWith(entries: entries);
      });

  /// Follows a renamed video across every playlist that holds it.
  ///
  /// The media id survives a rename on its own, so this is not what keeps the
  /// entry working today — it keeps the NAME fallback accurate, which is what
  /// would carry the entry through a later move.
  Future<void> renameEntry(String oldName, String newName) async {
    for (final p in _store.all()) {
      if (!p.entries.any((e) => e.displayName == oldName)) continue;
      await _store.put(p.copyWith(
        entries: p.entries
            .map((e) => e.displayName == oldName
                ? PlaylistEntry(mediaId: e.mediaId, displayName: newName)
                : e)
            .toList(),
      ));
    }
    state = _store.all();
  }

  /// Reads, transforms, writes. An unknown id falls through untouched rather
  /// than creating a playlist nobody asked for.
  Future<void> _update(String id, Playlist Function(Playlist) change) async {
    final current = _findById(id);
    if (current == null) return;
    await _store.put(change(current));
    state = _store.all();
  }

  /// Explicit loop rather than `firstOrNull` — this repo has no
  /// `package:collection` dependency and one call isn't worth adding it.
  Playlist? _findById(String id) {
    for (final p in _store.all()) {
      if (p.id == id) return p;
    }
    return null;
  }
}

final playlistsProvider =
    NotifierProvider<PlaylistsNotifier, List<Playlist>>(PlaylistsNotifier.new);
