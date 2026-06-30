import 'package:flutter/services.dart';
import '../interfaces/frame_extractor.dart';

/// Android implementation of [FrameExtractor] backed by MediaMetadataRetriever
/// via the `kivo/frames` MethodChannel.
///
/// Call [prepare] once per video, [frameAt] for each thumbnail, [release] on
/// close. [prepare] is idempotent for the same path (the Kotlin side reuses the
/// same retriever when the path hasn't changed).
class AndroidFrameExtractor implements FrameExtractor {
  static const MethodChannel _channel = MethodChannel('kivo/frames');

  @override
  Future<void> prepare(String path) async {
    await _channel.invokeMethod<void>('prepare', {'path': path});
  }

  @override
  Future<Uint8List?> frameAt(Duration position) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'frameAt',
      {'ms': position.inMilliseconds},
    );
    return bytes;
  }

  @override
  Future<void> release() async {
    await _channel.invokeMethod<void>('release');
  }
}
