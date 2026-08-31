import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/playback_engine.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';
import 'track_delay.dart';
import 'track_prefs_store.dart';

/// How long a controller waits for the taps to stop before telling mpv.
///
/// `setSubtitleDelay` / `setAudioDelay` are synchronous mpv calls on the UI
/// thread — the same one wedged at the top of the open background-hang ANR
/// trace. Holding the taps here means a dozen presses cost one native call,
/// not a dozen.
const trackDelayDebounce = Duration(milliseconds: 120);

/// One debounced, per-video track offset in milliseconds.
///
/// Subtitle and audio delay differ in exactly three things: which field of the
/// stored record they read, which field they write, and which engine method
/// they apply to. Everything else — the trailing debounce, the flush, keeping
/// up with the open video — is identical, so it lives here once rather than
/// twice.
///
/// The state is authoritative for the UI and updates on every tap; mpv and
/// Hive are brought in line on the trailing edge of [trackDelayDebounce].
abstract class TrackDelayNotifier extends Notifier<int> {
  Timer? _debounce;

  /// The offset this notifier owns, out of a stored record.
  int readStored(VideoTrackPrefs prefs);

  /// The same record with this notifier's offset replaced — `copyWith`, so the
  /// sibling offset and the hand-picked subtitle survive untouched.
  VideoTrackPrefs writeStored(VideoTrackPrefs prefs, int ms);

  Future<void> applyToEngine(PlaybackEngine engine, double seconds);

  @override
  int build() {
    ref.onDispose(() => _debounce?.cancel());
    final session = ref.watch(currentVideoProvider);
    if (session == null) return 0;
    final prefs = ref.read(trackPrefsStoreProvider).forKey(session.resumeKey);
    return prefs == null ? 0 : readStored(prefs);
  }

  void nudge(int steps) {
    if (ref.read(currentVideoProvider) == null) return;
    state = nudgeDelay(state, steps);
    _schedule();
  }

  /// Jumps straight to a value — how the drag bar reports the finger.
  ///
  /// Deliberately debounced like [nudge] rather than applied immediately: a
  /// drag emits dozens of these a second, and each one reaching mpv would be
  /// dozens of synchronous calls on the UI thread. The debounce that was built
  /// for tap bursts covers this without changing.
  void setTo(int ms) {
    if (ref.read(currentVideoProvider) == null) return;
    if (ms == state) return;
    state = ms;
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
    _debounce = Timer(trackDelayDebounce, () {
      _debounce = null;
      _apply();
    });
  }

  Future<void> _apply() async {
    final session = ref.read(currentVideoProvider);
    if (session == null) return;
    final ms = state;
    try {
      await applyToEngine(ref.read(playbackEngineProvider), ms / 1000);
      final store = ref.read(trackPrefsStoreProvider);
      final existing =
          store.forKey(session.resumeKey) ?? const VideoTrackPrefs();
      await store.put(session.resumeKey, writeStored(existing, ms));
    } catch (e) {
      // _schedule calls this from a Timer with nothing awaiting it, so a throw
      // from mpv or from the Hive write would be an unhandled async error in a
      // zone with no handler. The state stays what the HUD is already showing.
      debugPrint('TrackDelayNotifier._apply failed: $e');
    }
  }
}

class SubtitleSyncNotifier extends TrackDelayNotifier {
  @override
  int readStored(VideoTrackPrefs prefs) => prefs.subtitleDelayMs;

  @override
  VideoTrackPrefs writeStored(VideoTrackPrefs prefs, int ms) =>
      prefs.copyWith(subtitleDelayMs: ms);

  @override
  Future<void> applyToEngine(PlaybackEngine engine, double seconds) =>
      engine.setSubtitleDelay(seconds);
}

class AudioSyncNotifier extends TrackDelayNotifier {
  @override
  int readStored(VideoTrackPrefs prefs) => prefs.audioDelayMs;

  @override
  VideoTrackPrefs writeStored(VideoTrackPrefs prefs, int ms) =>
      prefs.copyWith(audioDelayMs: ms);

  @override
  Future<void> applyToEngine(PlaybackEngine engine, double seconds) =>
      engine.setAudioDelay(seconds);
}

final subtitleSyncProvider =
    NotifierProvider<SubtitleSyncNotifier, int>(SubtitleSyncNotifier.new);

final audioSyncProvider =
    NotifierProvider<AudioSyncNotifier, int>(AudioSyncNotifier.new);
