import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/frame_extractor_provider.dart';
import '../../platform/subtitle_finder_provider.dart';
import '../../ui/player/state/mini_player_state.dart';
import '../engine/playback_provider.dart';
import '../end_actions/end_flow.dart';
import '../end_actions/trash_queue.dart';
import '../library/played.dart';
import '../decoder/decoder_controller.dart';
import '../open/video_source.dart';
import '../resume/resume_plan.dart';
import '../sleep/sleep_timer.dart';
import '../tracks/apply_default_tracks.dart';
import '../tracks/subtitle_loader.dart';
import '../audio/audio_pipeline_controller.dart';
import '../tracks/track_prefs_store.dart';

/// App-level coordinator that advances the queue when a video ends WHILE
/// MINIMIZED to the mini-player. When the player is expanded, PlayerScreen owns
/// completion (its "Próximo" overlay); this returns immediately then, so there
/// is no double-advance (PlayerScreen is disposed while minimized). Instantiate
/// once by watching [autoplayCoordinatorProvider] (KivoApp does).
final autoplayCoordinatorProvider = Provider<AutoplayCoordinator>((ref) {
  final c = AutoplayCoordinator(ref);
  c.init();
  return c;
});

class AutoplayCoordinator {
  final Ref _ref;
  AutoplayCoordinator(this._ref);
  bool _advancing = false;

  // See PlayerScreen._endHandledFor: one ending per play-through.
  VideoSession? _endHandledFor;

  void init() {
    _ref.listen(completedProvider, (_, next) {
      if (next.value == true) _onCompleted();
    });
    _ref.listen<int>(sleepEpisodeEndProvider, (_, _) {
      _onCompleted(sleepStopped: true);
    });
    _ref.listen(playingProvider, (_, next) {
      if (next.value == true) _endHandledFor = null;
    });
  }

  void _onCompleted({bool sleepStopped = false}) {
    if (_advancing) return;
    // Expanded → PlayerScreen handles it (with the overlay). Only act minimized.
    if (!_ref.read(playerMinimizedProvider)) return;
    final session = _ref.read(currentVideoProvider);
    if (session == null || identical(_endHandledFor, session)) return;
    _endHandledFor = session;
    final d = decideEnd(_ref.read, session: session, sleepStopped: sleepStopped);
    final next = d.next;
    // No cards down here: whatever was planned happens now.
    final after = d.plan.after;
    if (after != null) {
      _ref.read(playbackEngineProvider).pause();
      if (_ref.read(sleepTimerProvider) != null) {
        _ref.read(sleepTimerProvider.notifier).cancel();
      }
      unawaited(_runAfter(after, d.trash));
      return;
    }
    if (!d.plan.advance) {
      if (d.sleepStop && next != null && d.autoplayEnabled && !d.loopActive) {
        _ref.read(playbackEngineProvider).pause();
        _ref.read(sleepTimerProvider.notifier).cancel();
      }
      unawaited(_stage(d.trash));
      return;
    }
    _advance(next!, trash: d.trash);
  }

  Future<void> _stage(EndTrash? t, {String? unlessPlaying}) async {
    if (t == null || t.item.uri == unlessPlaying) return;
    await _ref.read(trashQueueProvider.notifier).stage(t.item, ended: t.session);
  }

  /// The minimized flavour of «Después»: there is no full-screen player to
  /// close or screen to keep awake here.
  Future<void> _runAfter(AfterEnd after, EndTrash? trash) async {
    // Staged first: closing below may flush the queue right away.
    await _stage(trash);
    switch (after) {
      case AfterEnd.keepGoing:
      case AfterEnd.screenOff:
        return; // already paused
      case AfterEnd.closePlayer:
        // Same as the mini-bar's ✕ — and that is a moment to confirm the
        // batched deletions.
        _ref.read(playerMinimizedProvider.notifier).state = false;
        _ref.read(trashFlushRequestProvider.notifier).state++;
      case AfterEnd.closeApp:
        _ref.read(suppressTrashFlushProvider.notifier).state = true;
        _ref.read(playerMinimizedProvider.notifier).state = false;
        _ref.read(currentVideoProvider.notifier).clear();
        _ref.read(appExitProvider)();
    }
  }

  Future<void> _advance(VideoSession next, {EndTrash? trash}) async {
    _advancing = true;
    final engine = _ref.read(playbackEngineProvider);
    final settings = _ref.read(settingsProvider);
    try {
      _ref.read(sleepTimerProvider.notifier).onAutoplayAdvance();
      _ref.read(currentVideoProvider.notifier).advanceTo(next);
      unawaited(_stage(trash, unlessPlaying: next.playbackPath));
      if (!settings.incognito) {
        _ref.read(playedStoreProvider).markPlayed(next.resumeKey);
      }
      final plan = planResume(
        _ref.read(resumeServiceProvider).positionFor(next.resumeKey),
        settings.resumeBehavior);
      await _ref
          .read(decoderControllerProvider)
          .open(next, startAt: plan.startAt);
      await engine.play();
      unawaited(applyDefaultTracks(
        engine: engine, settings: settings, session: next,
        subtitleFinder: _ref.read(subtitleFinderProvider),
        subtitlePrefs: _ref.read(trackPrefsStoreProvider),
        subtitleLoader: _ref.read(subtitleLoaderProvider),
        applyAudio: _ref.read(audioPipelineProvider).onOpen));
      _refreshMiniThumb(next.playbackPath);
    } finally {
      _advancing = false;
    }
  }

  Future<void> _refreshMiniThumb(String path) async {
    try {
      final frames = _ref.read(frameExtractorProvider);
      await frames.prepare(path);
      final bytes = await frames.frameAt(Duration.zero);
      _ref.read(miniPlayerThumbnailProvider.notifier).state = bytes;
    } catch (_) {
      // Best-effort — a failed capture just leaves the previous/placeholder art.
    }
  }
}
