import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_file_ops.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/media_file_ops_provider.dart';
import '../open/video_source.dart'; // resumeServiceProvider
import '../tracks/subtitle_importer.dart';
import '../tracks/subtitle_prefs_store.dart';
import 'continue_watching.dart';
import 'media_index.dart';
import 'played.dart';

/// Orchestrates a library video's file operations and their side effects:
/// refreshing the media index, and keeping the resume, played, and subtitle
/// prefs stores (keyed by file name) consistent — migrating them on rename,
/// clearing them on delete.
class VideoActionsController {
  final Ref _ref;
  VideoActionsController(this._ref);

  Future<void> share(VideoItem v) =>
      _ref.read(mediaFileOpsProvider).share(v.uri);

  Future<FileOpStatus> delete(VideoItem v) async {
    final status = await _ref.read(mediaFileOpsProvider).delete(v.uri);
    if (status != FileOpStatus.ok) return status;
    await _ref.read(resumeServiceProvider).clear(v.name);
    await _ref.read(playedStoreProvider).remove(v.name);
    await _discardImportedSubtitle(v.name);
    await _ref.read(subtitlePrefsStoreProvider).remove(v.name);
    await _refreshLibrary();
    return status;
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
    final path = _ref.read(subtitlePrefsStoreProvider).forKey(key)?.subtitlePath;
    if (path == null) return;
    await _ref.read(subtitleImporterProvider).discard(path);
  }

  Future<RenameOutcome> rename(VideoItem v, String newBaseName) async {
    final outcome = await _ref.read(mediaFileOpsProvider).rename(v.uri, newBaseName);
    if (outcome.status != FileOpStatus.ok || outcome.newName == null) return outcome;
    final newName = outcome.newName!;
    await _ref.read(resumeServiceProvider).rename(v.name, newName);
    await _ref.read(subtitlePrefsStoreProvider).rename(v.name, newName);
    final played = _ref.read(playedStoreProvider);
    if (played.isPlayed(v.name)) {
      await played.markPlayed(newName);
      await played.remove(v.name);
    }
    await _refreshLibrary();
    return outcome;
  }

  Future<FileOpStatus> deleteMany(List<VideoItem> videos) async {
    final status = await _ref.read(mediaFileOpsProvider).deleteMany(
        videos.map((v) => v.uri).toList());
    if (status != FileOpStatus.ok) return status;
    final resume = _ref.read(resumeServiceProvider);
    final played = _ref.read(playedStoreProvider);
    final subtitlePrefs = _ref.read(subtitlePrefsStoreProvider);
    for (final v in videos) {
      await resume.clear(v.name);
      await played.remove(v.name);
      await _discardImportedSubtitle(v.name);
      await subtitlePrefs.remove(v.name);
    }
    await _refreshLibrary();
    return status;
  }

  Future<void> shareMany(List<VideoItem> videos) =>
      _ref.read(mediaFileOpsProvider).shareMany(videos.map((v) => v.uri).toList());

  Future<void> _refreshLibrary() async {
    await _ref.read(mediaIndexProvider.notifier).refresh();
    _ref.invalidate(continueWatchingProvider);
    _ref.invalidate(playedKeysProvider);
  }
}

final videoActionsProvider =
    Provider<VideoActionsController>((ref) => VideoActionsController(ref));
