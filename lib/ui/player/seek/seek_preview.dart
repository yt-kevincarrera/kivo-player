import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/frame_extractor_provider.dart';
import '../../../platform/interfaces/frame_extractor.dart';
import '../../../player/open/video_source.dart';

/// Current scrub target while dragging the seek bar; null when not dragging.
final scrubProvider = StateProvider<Duration?>((ref) => null);

/// Holds the seek bar at the just-committed target after release until real
/// playback position catches up — avoids the slider snapping back to the old
/// position for a few frames while the seek lands.
final pendingSeekProvider = StateProvider<Duration?>((ref) => null);

/// Latest preview frame bytes for the bubble (null = none/loading).
final seekPreviewFrameProvider = StateProvider<Uint8List?>((ref) {
  ref.watch(currentVideoProvider.select((s) => s?.playbackPath));
  return null;
});

/// In-progress horizontal-swipe seek: the [target] position and the [from]
/// position the drag began at (for an exact delta label); null when no such
/// gesture is active. Kept separate from [scrubProvider] (the seek bar's) so the
/// centered gesture preview and the seek-bar bubble never render at once.
final gestureSeekProvider = StateProvider<({Duration target, Duration from})?>(
  (ref) => null,
);

final seekPreviewControllerProvider = Provider<SeekPreviewController>((ref) {
  // Timestamps/cache belong to one source, not every video in the queue.
  ref.watch(currentVideoProvider.select((s) => s?.playbackPath));
  final controller = SeekPreviewController(
    extractor: ref.read(frameExtractorProvider),
    onFrame: (b) => ref.read(seekPreviewFrameProvider.notifier).state = b,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Buckets scrub positions to 1 s, LRU-caches the last [capacity] frames, and
/// coalesces requests so at most one extraction runs at a time — a newer
/// position arriving mid-flight replaces the pending one (intermediates drop).
class SeekPreviewController {
  SeekPreviewController({
    required FrameExtractor extractor,
    required this.onFrame,
    this.capacity = 30,
  }) : _extractor = extractor;

  final FrameExtractor _extractor;
  final void Function(Uint8List? bytes) onFrame;
  final int capacity;

  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  bool _inFlight = false;
  int? _pendingBucket;
  int _generation = 0;
  bool _disposed = false;
  bool _decoderRequested = false;
  bool _cachedTargetShown = false;

  /// A running native decode cannot be interrupted safely. Drop its result
  /// and the queued target, then release its decoder on the native executor.
  /// No second preview starts beside the actual post-release playback seek.
  void cancel() {
    if (_disposed) return;
    ++_generation;
    _pendingBucket = null;
    onFrame(null);
    _suspendDecoder();
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    _pendingBucket = null;
    _cache.clear();
    _suspendDecoder();
  }

  void _suspendDecoder() {
    if (!_decoderRequested) return;
    _decoderRequested = false;
    unawaited(
      _extractor.suspend().catchError((Object _) {
        // Preview cleanup must not prevent the user's playback seek.
      }),
    );
  }

  void request(Duration position) {
    if (_disposed) return;
    final bucket = position.inSeconds;
    final cached = _get(bucket);
    _cachedTargetShown = cached != null;
    if (cached != null) {
      _pendingBucket = null;
      onFrame(cached);
      return;
    }
    _pendingBucket = bucket;
    if (!_inFlight) _drain();
  }

  Future<void> _drain() async {
    while (!_disposed && _pendingBucket != null) {
      final generation = _generation;
      final bucket = _pendingBucket!;
      _pendingBucket = null;
      final cached = _get(bucket);
      if (cached != null) {
        onFrame(cached);
        continue;
      }
      _inFlight = true;
      try {
        _decoderRequested = true;
        final bytes = await _extractor.frameAt(Duration(seconds: bucket));
        if (!_disposed && generation == _generation && bytes != null) {
          _put(bucket, bytes);
          // Surface every completed frame so the bubble tracks the finger
          // continuously (each lags by one extraction). Suppressing while a
          // newer request is pending froze the preview during a fast drag.
          if (!_cachedTargetShown) onFrame(bytes);
        }
      } catch (_) {
        // A native extraction failure must not strand _inFlight=true (which
        // would permanently deadlock the controller); the finally resets it.
      } finally {
        _inFlight = false;
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
