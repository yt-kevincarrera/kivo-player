import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/player/state/video_ready_state.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';
import 'chapter.dart';

/// The open video's chapters, empty until they have been read.
///
/// Deliberately **not** read during the video open. mpv exposes chapters one
/// property at a time and each read is a synchronous FFI call on the UI
/// isolate, so a twenty-chapter file would land forty of them at the busiest
/// moment the app has — decode starting, tracks applying, resume seeking.
/// Waiting for the first frame moves that cost to a point where playback is
/// already stable, and it is invisible.
///
/// A file with no chapters costs exactly one read, so the common case is
/// effectively free.
class ChaptersNotifier extends Notifier<List<MediaChapter>> {
  /// Bumped on every build. A read that started under an older generation
  /// belongs to a video that is no longer open, so its answer is dropped
  /// rather than written over the current one.
  int _generation = 0;
  bool _disposed = false;

  @override
  List<MediaChapter> build() {
    // A new video means new chapters — and none until they are read.
    ref.watch(currentVideoProvider);

    _disposed = false;
    final generation = ++_generation;
    ref.onDispose(() => _disposed = true);

    if (ref.watch(videoFrameReadyProvider)) {
      // Not awaited: this returns the state the UI shows right now, and the
      // read replaces it a moment later.
      _read(generation);
    }
    return const [];
  }

  Future<void> _read(int generation) async {
    final chapters = await ref.read(playbackEngineProvider).chapters();
    if (_disposed || generation != _generation) return;
    state = chapters;
  }
}

final chaptersProvider = NotifierProvider<ChaptersNotifier, List<MediaChapter>>(
  ChaptersNotifier.new,
);

/// The chapter the playhead is in, or null outside any.
final currentChapterProvider = Provider<MediaChapter?>((ref) {
  final chapters = ref.watch(chaptersProvider);
  final position = ref.watch(positionProvider).value ?? Duration.zero;
  final index = currentChapterIndex(chapters, position);
  return index < 0 ? null : chapters[index];
});
