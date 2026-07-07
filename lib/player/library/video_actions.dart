import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_file_ops.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/media_file_ops_provider.dart';
import '../open/video_source.dart'; // resumeServiceProvider
import 'continue_watching.dart';
import 'media_index.dart';
import 'played.dart';

/// Orchestrates a library video's file operations and their side effects:
/// refreshing the media index, and keeping the resume + played stores (keyed by
/// file name) consistent — migrating them on rename, clearing them on delete.
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
    await _refreshLibrary();
    return status;
  }

  Future<RenameOutcome> rename(VideoItem v, String newBaseName) async {
    final outcome = await _ref.read(mediaFileOpsProvider).rename(v.uri, newBaseName);
    if (outcome.status != FileOpStatus.ok || outcome.newName == null) return outcome;
    final newName = outcome.newName!;
    await _ref.read(resumeServiceProvider).rename(v.name, newName);
    final played = _ref.read(playedStoreProvider);
    if (played.isPlayed(v.name)) {
      await played.markPlayed(newName);
      await played.remove(v.name);
    }
    await _refreshLibrary();
    return outcome;
  }

  Future<void> _refreshLibrary() async {
    await _ref.read(mediaIndexProvider.notifier).refresh();
    _ref.invalidate(continueWatchingProvider);
    _ref.invalidate(playedKeysProvider);
  }
}

final videoActionsProvider =
    Provider<VideoActionsController>((ref) => VideoActionsController(ref));
