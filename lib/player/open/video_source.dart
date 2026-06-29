import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../resume/resume_service.dart';
import '../queue/folder_queue_scanner.dart';
import '../queue/file_system_lister.dart';

/// An immutable snapshot of the currently-opened video and its folder queue.
///
/// **Resume-key and folder-queue stability assumption (Plan 1):**
/// Both the resume service (keyed by [path]) and the folder-queue scanner
/// (which lists siblings of [path]) assume [path] is a stable filesystem path
/// as supplied by the file picker (e.g. `/storage/emulated/0/Movies/ep1.mkv`).
///
/// When the app receives a share intent on Android, the system may deliver a
/// `content://` URI or a transient cache copy whose path changes between
/// launches. In those cases resume lookup will silently miss and the folder
/// scanner will return an empty sibling list (falling back to a single-item
/// queue containing only [path] — no crash). Normalizing `content://` URIs to
/// stable paths is deferred to a later plan.
class VideoSession {
  final String path;
  final List<String> queue;
  final int index;
  const VideoSession({required this.path, required this.queue, required this.index});
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

  void open(VideoSession session) => state = session;

  void openPath(String path) {
    final queue = ref.read(queueScannerProvider).siblingsOf(path);
    final index = queue.indexOf(path);
    state = VideoSession(
      path: path,
      queue: queue.isEmpty ? [path] : queue,
      index: index < 0 ? 0 : index,
    );
  }
}

final currentVideoProvider =
    NotifierProvider<CurrentVideoNotifier, VideoSession?>(CurrentVideoNotifier.new);
