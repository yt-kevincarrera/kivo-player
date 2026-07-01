import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../player/library/library_query.dart';
import '../resume/resume_service.dart';
import '../queue/folder_queue_scanner.dart';
import '../queue/file_system_lister.dart';

/// An immutable snapshot of the currently-opened video and its folder queue.
///
/// [playbackPath] is the path or content:// URI that media_kit opens.
/// [displayName] is the stable human-readable file name used as the resume key.
class VideoSession {
  final String playbackPath; // file path or content:// uri opened by media_kit
  final String displayName;  // file name — the stable resume key
  final List<String> queue;  // folder playbackPaths, natural order
  final int index;
  final String? folder; // set only when opened from the library — enables external-subtitle discovery
  const VideoSession({
    required this.playbackPath,
    required this.displayName,
    required this.queue,
    required this.index,
    this.folder,
  });
  String get resumeKey => displayName;
}

final resumeServiceProvider = Provider<ResumeService>((ref) {
  throw UnimplementedError('resumeServiceProvider must be overridden');
});

final queueScannerProvider = Provider<FolderQueueScanner>(
  (ref) => FolderQueueScanner(IoFileSystemLister()),
);

class CurrentVideoNotifier extends Notifier<VideoSession?> {
  @override
  VideoSession? build() => null;

  /// Direct session open (used by tests and future callers that construct their own session).
  void open(VideoSession session) => state = session;

  /// File-picker open: single-item queue (the picker gives a cache copy, no folder).
  void openPath(String path) {
    final name = basenameOf(path);
    state = VideoSession(
        playbackPath: path, displayName: name, queue: [path], index: 0);
  }

  /// Library open: queue = the current video's folder, natural order.
  void openInFolder(VideoItem current, List<VideoItem> all) {
    final folder = folderQueueFor(all, current);
    final idx = folder.indexWhere((v) => v.uri == current.uri);
    state = VideoSession(
      playbackPath: current.uri,
      displayName: current.name,
      queue: folder.map((v) => v.uri).toList(),
      index: idx < 0 ? 0 : idx,
      folder: current.folder,
    );
  }
}

final currentVideoProvider =
    NotifierProvider<CurrentVideoNotifier, VideoSession?>(CurrentVideoNotifier.new);
