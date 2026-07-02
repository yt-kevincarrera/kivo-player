import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';

/// In-app "Solo audio" mode: video track off, black surface, controls intact.
/// A tool of the moment — dies on video change and on player exit; never
/// persisted.
final audioOnlyProvider =
    NotifierProvider<AudioOnlyNotifier, bool>(AudioOnlyNotifier.new);

class AudioOnlyNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(currentVideoProvider, (prev, next) {
      if (state && prev != next) {
        _setVideo(true);
        state = false;
      }
    });
    return false;
  }

  void _setVideo(bool on) =>
      ref.read(playbackEngineProvider).setVideoTrackEnabled(on);

  void toggle() {
    final next = !state;
    _setVideo(!next);
    state = next;
  }

  /// Called from PlayerScreen's dispose (via a notifier cached in initState —
  /// never ref.read in dispose).
  void disable() {
    if (!state) return;
    _setVideo(true);
    state = false;
  }
}
