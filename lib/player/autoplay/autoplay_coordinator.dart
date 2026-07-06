import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/frame_extractor_provider.dart';
import '../../platform/subtitle_finder_provider.dart';
import '../../ui/player/state/mini_player_state.dart';
import '../engine/playback_provider.dart';
import '../library/played.dart';
import '../loop/ab_loop.dart';
import '../open/video_source.dart';
import '../resume/resume_plan.dart';
import '../sleep/sleep_timer.dart';
import '../tracks/apply_default_tracks.dart';
import 'autoplay_logic.dart';

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

  void init() {
    _ref.listen(completedProvider, (_, next) {
      if (next.value == true) _onCompleted();
    });
  }

  void _onCompleted() {
    if (_advancing) return;
    // Expanded → PlayerScreen handles it (with the overlay). Only act minimized.
    if (!_ref.read(playerMinimizedProvider)) return;
    final settings = _ref.read(settingsProvider);
    final loopActive = _ref.read(abLoopProvider)?.phase == AbLoopPhase.active;
    final sleepStop = sleepStopsHere(_ref.read(sleepTimerProvider));
    final next = _ref.read(currentVideoProvider.notifier).peekNext();
    final go = shouldAutoplay(
      enabled: settings.autoplayNext,
      hasNext: next != null,
      loopActive: loopActive,
      sleepStopsHere: sleepStop,
    );
    if (!go) {
      if (sleepStop && next != null && settings.autoplayNext && !loopActive) {
        _ref.read(playbackEngineProvider).pause();
        _ref.read(sleepTimerProvider.notifier).cancel();
      }
      return;
    }
    _advance(next!);
  }

  Future<void> _advance(VideoSession next) async {
    _advancing = true;
    final engine = _ref.read(playbackEngineProvider);
    final settings = _ref.read(settingsProvider);
    try {
      _ref.read(sleepTimerProvider.notifier).onAutoplayAdvance();
      _ref.read(currentVideoProvider.notifier).advanceTo(next);
      _ref.read(playedStoreProvider).markPlayed(next.resumeKey);
      final plan = planResume(
        _ref.read(resumeServiceProvider).positionFor(next.resumeKey),
        settings.resumeBehavior);
      await engine.open(next.playbackPath, startAt: plan.startAt);
      await engine.play();
      applyDefaultTracks(
        engine: engine, settings: settings, session: next,
        subtitleFinder: _ref.read(subtitleFinderProvider));
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
