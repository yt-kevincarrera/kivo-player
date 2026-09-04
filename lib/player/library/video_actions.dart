import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_file_ops.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/media_file_ops_provider.dart';
import '../bookmarks/bookmark_store.dart';
import '../open/video_source.dart'; // resumeServiceProvider
import '../playlists/playlist_controller.dart';
import '../tracks/subtitle_importer.dart';
import '../tracks/track_prefs_store.dart';
import 'continue_watching.dart';
import 'media_index.dart';
import 'played.dart';

/// Orchestrates a library video's file operations and their side effects:
/// refreshing the media index, and keeping the resume, played, subtitle
/// prefs, and playlist stores (keyed by file name) consistent — migrating
/// them on rename, clearing them on delete. Playlists and bookmarks are the
/// exception: delete deliberately does NOT touch them, so a video's entry
/// (or its bookmarks) survives its own deletion — an SD card unplugged for
/// an afternoon must not destroy either, and a video deleted by mistake and
/// restored keeps whatever was marked in it.
class VideoActionsController {
  final Ref _ref;
  VideoActionsController(this._ref);

  Future<void> share(VideoItem v) =>
      _ref.read(mediaFileOpsProvider).share(v.uri);

  Future<FileOpStatus> delete(VideoItem v) async {
    final ops = _ref.read(mediaFileOpsProvider);
    final status = await ops.delete(v.uri);
    if (status != FileOpStatus.ok) return status;
    // A trashed file is not gone: it can come back from the system trash for
    // 30 days, and it should come back WHOLE — position, played mark, the
    // subtitle it had. Only a permanent delete clears the name-keyed stores.
    if (!ops.movesToTrash) await _forgetVideo(v.name);
    await _refreshLibrary();
    return status;
  }

  Future<void> _forgetVideo(String name) async {
    await _ref.read(resumeServiceProvider).clear(name);
    await _ref.read(playedStoreProvider).remove(name);
    await _discardImportedSubtitle(name);
    await _ref.read(trackPrefsStoreProvider).remove(name);
  }

  /// Deletes the app-owned subtitle copy, if this video had one.
  ///
  /// Rename does not call this: the stored path is absolute, so it keeps
  /// working under the new key. It does leave the copy named after the OLD
  /// key, and the importer's sweep matches `stem == videoKey` exactly, so a
  /// later import under the new key will not collect it — that file is then
  /// orphaned for good. Deliberate for now: it is a few KB in app-private
  /// storage with no effect on behaviour, and cleaning it up properly means
  /// giving SubtitleImporter a move/rename operation it does not have.
  Future<void> _discardImportedSubtitle(String key) async {
    final path = _ref.read(trackPrefsStoreProvider).forKey(key)?.subtitlePath;
    if (path == null) return;
    await _ref.read(subtitleImporterProvider).discard(path);
  }

  Future<RenameOutcome> rename(VideoItem v, String newBaseName) async {
    final outcome = await _ref
        .read(mediaFileOpsProvider)
        .rename(v.uri, newBaseName);
    if (outcome.status != FileOpStatus.ok || outcome.newName == null) {
      return outcome;
    }
    final newName = outcome.newName!;
    await _ref.read(resumeServiceProvider).rename(v.name, newName);
    await _ref.read(trackPrefsStoreProvider).rename(v.name, newName);
    await _ref
        .read(playlistsProvider.notifier)
        .renameEntry(v.id, v.name, newName);
    await _ref.read(bookmarkStoreProvider).rename(v.name, newName);
    final played = _ref.read(playedStoreProvider);
    if (played.isPlayed(v.name)) {
      await played.markPlayed(newName);
      await played.remove(v.name);
    }
    await _refreshLibrary();
    return outcome;
  }

  Future<FileOpStatus> deleteMany(List<VideoItem> videos) async {
    final ops = _ref.read(mediaFileOpsProvider);
    final status = await ops.deleteMany(videos.map((v) => v.uri).toList());
    if (status != FileOpStatus.ok) return status;
    // Same rule as delete(): trashed videos keep everything.
    if (!ops.movesToTrash) {
      for (final v in videos) {
        await _forgetVideo(v.name);
      }
    }
    await _refreshLibrary();
    return status;
  }

  Future<void> shareMany(List<VideoItem> videos) => _ref
      .read(mediaFileOpsProvider)
      .shareMany(videos.map((v) => v.uri).toList());

  /// Marks (or unmarks) a video as played/seen. Invalidates
  /// [playedKeysProvider] so the "Nuevo" badge in the library grid updates
  /// immediately.
  Future<void> setPlayed(VideoItem v, bool played) async {
    final store = _ref.read(playedStoreProvider);
    if (played) {
      await store.markPlayed(v.name);
    } else {
      await store.remove(v.name);
    }
    _ref.invalidate(playedKeysProvider);
  }

  /// Drops a video's saved resume position — e.g. it was opened by mistake
  /// and shouldn't linger in "Continuar viendo". Invalidates
  /// [continueWatchingProvider] so the carousel drops the card at once.
  Future<void> clearResume(VideoItem v) async {
    await _ref.read(resumeServiceProvider).clear(v.name);
    _ref.invalidate(continueWatchingProvider);
  }

  Future<void> _refreshLibrary() async {
    await _ref.read(mediaIndexProvider.notifier).refresh();
    _ref.invalidate(continueWatchingProvider);
    _ref.invalidate(playedKeysProvider);
  }
}

final videoActionsProvider = Provider<VideoActionsController>(
  (ref) => VideoActionsController(ref),
);
