import 'dart:typed_data';
import '../../core/media/video_identity.dart';

class VideoItem {
  final String id;
  final String uri;
  final String name;
  final String folder;
  final int durationMs;
  final int sizeBytes;
  final int dateAddedMs;
  final int width; // px, 0 if unknown
  final int height; // px, 0 if unknown
  final String path; // MediaStore RELATIVE_PATH, '' if unknown
  final String filePath; // full storage path, when MediaStore supplies one
  String get key => filePath.isNotEmpty
      ? videoIdentity(filePath, name)
      : videoIdentity(uri, name, path: path);
  const VideoItem({
    required this.id,
    required this.uri,
    required this.name,
    required this.folder,
    required this.durationMs,
    required this.sizeBytes,
    required this.dateAddedMs,
    this.width = 0,
    this.height = 0,
    this.path = '',
    this.filePath = '',
  });
}

/// Discovers the device's videos. Android: MediaStore. iOS: later.
abstract class MediaIndexer {
  Future<List<VideoItem>> scan();
  Future<Uint8List?> thumbnail(String id);
}
