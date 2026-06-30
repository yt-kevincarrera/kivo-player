import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/frame_extractor_provider.dart';
import '../../../platform/interfaces/frame_extractor.dart';

/// Current scrub target while dragging the seek bar; null when not dragging.
final scrubProvider = StateProvider<Duration?>((ref) => null);

/// Latest preview frame bytes for the bubble (null = none/loading).
final seekPreviewFrameProvider = StateProvider<Uint8List?>((ref) => null);

final seekPreviewControllerProvider = Provider<SeekPreviewController>((ref) {
  return SeekPreviewController(
    extractor: ref.read(frameExtractorProvider),
    onFrame: (b) => ref.read(seekPreviewFrameProvider.notifier).state = b,
  );
});

/// Buckets scrub positions to 1 s, LRU-caches the last [capacity] frames, and
/// coalesces requests so at most one extraction runs at a time — a newer
/// position arriving mid-flight replaces the pending one (intermediates drop).
class SeekPreviewController {
  SeekPreviewController(
      {required FrameExtractor extractor,
      required this.onFrame,
      this.capacity = 30})
      : _extractor = extractor;

  final FrameExtractor _extractor;
  final void Function(Uint8List? bytes) onFrame;
  final int capacity;

  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  bool _inFlight = false;
  int? _pendingBucket;

  void request(Duration position) {
    final bucket = position.inSeconds;
    final cached = _get(bucket);
    if (cached != null) {
      onFrame(cached);
      return;
    }
    _pendingBucket = bucket;
    if (!_inFlight) _drain();
  }

  Future<void> _drain() async {
    while (_pendingBucket != null) {
      final bucket = _pendingBucket!;
      _pendingBucket = null;
      final cached = _get(bucket);
      if (cached != null) {
        onFrame(cached);
        continue;
      }
      _inFlight = true;
      final bytes = await _extractor.frameAt(Duration(seconds: bucket));
      _inFlight = false;
      if (bytes != null) {
        _put(bucket, bytes);
        // Only surface if no newer request superseded this one mid-flight.
        if (_pendingBucket == null) onFrame(bytes);
      }
    }
  }

  Uint8List? _get(int bucket) {
    final v = _cache.remove(bucket);
    if (v != null) _cache[bucket] = v; // promote to most-recently-used
    return v;
  }

  void _put(int bucket, Uint8List bytes) {
    _cache.remove(bucket);
    _cache[bucket] = bytes;
    if (_cache.length > capacity) _cache.remove(_cache.keys.first);
  }
}
