import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../resume/resume_service.dart';
import '../queue/folder_queue_scanner.dart';
import '../queue/file_system_lister.dart';

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
