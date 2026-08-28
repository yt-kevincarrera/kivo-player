import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/playback_provider.dart';
import '../open/video_source.dart';
import 'subtitle_delay.dart';
import 'subtitle_prefs_store.dart';

/// How long the controller waits for the taps to stop before telling mpv.
///
/// `setSubtitleDelay` is a synchronous mpv call on the UI thread — the same
/// one wedged at the top of the open background-hang ANR trace. Holding the
/// taps here means a dozen presses cost one native call, not a dozen.
const subtitleSyncDebounce = Duration(milliseconds: 120);

/// The subtitle offset, in milliseconds, for the video that is open.
///
/// The state is authoritative for the UI and updates on every tap; mpv and
/// Hive are brought in line on the trailing edge of [subtitleSyncDebounce].
class SubtitleSyncNotifier extends Notifier<int> {
  Timer? _debounce;

  @override
  int build() {
    ref.onDispose(() => _debounce?.cancel());
    final session = ref.watch(currentVideoProvider);
    if (session == null) return 0;
    return ref.read(subtitlePrefsStoreProvider)
            .forKey(session.resumeKey)
            ?.delayMs ??
        0;
  }

  void nudge(int steps) {
    if (ref.read(currentVideoProvider) == null) return;
    state = nudgeSubtitleDelay(state, steps);
    _schedule();
  }

  void reset() {
    if (ref.read(currentVideoProvider) == null) return;
    state = 0;
    _schedule();
  }

  /// Applies whatever is pending right now. Called when the HUD closes so the
  /// last nudge is never dropped on the floor.
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    await _apply();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(subtitleSyncDebounce, () {
      _debounce = null;
      _apply();
    });
  }

  Future<void> _apply() async {
    final session = ref.read(currentVideoProvider);
    if (session == null) return;
    final ms = state;
    await ref.read(playbackEngineProvider).setSubtitleDelay(ms / 1000);
    final store = ref.read(subtitlePrefsStoreProvider);
    final existing = store.forKey(session.resumeKey) ?? const VideoSubtitlePrefs();
    await store.put(session.resumeKey, existing.copyWith(delayMs: ms));
  }
}

final subtitleSyncProvider =
    NotifierProvider<SubtitleSyncNotifier, int>(SubtitleSyncNotifier.new);
