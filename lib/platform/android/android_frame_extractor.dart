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
  bool _prepared = false;
  int _generation = 0;

  @override
  Future<void> prepare(String path) async {
    final generation = ++_generation;
    _prepared = false;
    try {
      await _channel.invokeMethod<void>('prepare', {'path': path});
      if (generation == _generation) _prepared = true;
    } on PlatformException catch (e) {
      // Android's thumbnail decoder supports fewer codecs than libmpv.
      // Missing previews must not fail otherwise playable videos.
      if (e.code != 'PREPARE_FAILED') rethrow;
    }
  }

  @override
  Future<Uint8List?> frameAt(Duration position) async {
    if (!_prepared) return null;
    final generation = _generation;
    final bytes = await _channel.invokeMethod<Uint8List>(
      'frameAt',
      {'ms': position.inMilliseconds},
    );
    return generation == _generation && _prepared ? bytes : null;
  }

  @override
  Future<void> release() async {
    ++_generation;
    _prepared = false;
    await _channel.invokeMethod<void>('release');
  }
}
