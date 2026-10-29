import 'dart:typed_data';

/// Extracts still frames from the current video for the seek-preview bubble.
/// Android-only for now (MediaMetadataRetriever); iOS fills this in later.
abstract class FrameExtractor {
  /// Prepare/reuse an extractor for [path]. Idempotent for the same path.
  /// A format unsupported by the thumbnail decoder can yield no frames even
  /// when the playback engine can play it.
  Future<void> prepare(String path);

  /// Nearest (keyframe) frame to [position] as JPEG bytes, or null.
  Future<Uint8List?> frameAt(Duration position);

  /// Release native resources (call on close or when switching videos).
  Future<void> release();
}
