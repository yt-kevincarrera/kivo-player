class VideoItem {
  final String id;
  final String uri;
  final String name;
  final String folder;
  final int durationMs;
  final int sizeBytes;
  final int dateAddedMs;
  const VideoItem({
    required this.id,
    required this.uri,
    required this.name,
    required this.folder,
    required this.durationMs,
    required this.sizeBytes,
    required this.dateAddedMs,
  });
}

/// Discovers the device's videos. Android: MediaStore. iOS: later.
abstract class MediaIndexer {
  Future<List<VideoItem>> scan();
}
