import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/device_controls_provider.dart';
import '../../platform/volume_keys.dart';
import '../../player/control/gesture_math.dart';
import '../../platform/interfaces/device_controls.dart';
import '../../platform/interfaces/pip_controller.dart';
import '../../platform/pip_controller_provider.dart';
import '../../player/control/player_controller.dart';
import '../../platform/frame_extractor_provider.dart';
import '../../platform/interfaces/frame_extractor.dart';
import '../../platform/subtitle_finder_provider.dart';
import '../../player/autoplay/autoplay_logic.dart';
import '../../player/background/audio_only.dart';
import '../../player/engine/playback_engine.dart';
import '../../player/engine/playback_provider.dart';
import '../../player/library/played.dart';
import '../../player/loop/ab_loop.dart';
import '../../player/open/video_source.dart';
import '../../player/resume/resume_plan.dart';
import '../../player/resume/resume_service.dart';
import '../../player/sleep/sleep_timer.dart';
import '../../player/tracks/apply_default_tracks.dart';
import 'audio_only/audio_only_view.dart';
import 'autoplay/autoplay_overlay.dart';
import 'controls/controls_overlay.dart';
import 'controls/flash_overlay.dart';
import 'controls/info_overlay.dart';
import 'controls/resume_prompt.dart';
import 'gestures/player_gestures.dart';
import 'gestures/ripple_overlay.dart';
import 'hud/hud_overlay.dart';
import 'seek/gesture_seek_preview.dart';
import 'sleep/sleep_warning_toast.dart';
import 'speed/speed_ladder_overlay.dart';
import 'state/aspect_state.dart';
import 'state/autoplay_state.dart';
import 'state/dismiss_state.dart';
import 'state/hud_state.dart';
import 'state/mini_player_state.dart';
import 'state/orientation_state.dart';
import 'state/pip_state.dart';
import 'state/player_dismiss_state.dart';
import 'state/video_ready_state.dart';
import 'state/queue_strip_state.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  VideoController? _controller;
  Duration _lastPosition = Duration.zero;
  bool _previewCaptured = false; // guards one-shot eager mini-preview per drag
  bool _advancing = false; // guards autoplay against re-entrant completed events
  Duration _lastDuration = Duration.zero;
  String? _resumeKey;
  late final DeviceControls _deviceControls;
  late final PlaybackEngine _engine;
  late final ResumeService _resume;
  late final FrameExtractor _frames;
  late final AudioOnlyNotifier _audioOnly;
  late final StateController<Uint8List?> _miniThumb;
  late final StateController<PlayerDismissApi?> _dismissApi;
  late final PipController _pip;
  StreamSubscription<double>? _sysVolSub;
  StreamSubscription<bool>? _frameSub; // engine's first-frame signal → videoFrameReadyProvider
  StreamSubscription<VolumeKeyEvent>? _volKeySub;
  Timer? _saveTimer;
  late final AnimationController _dismissCtl;
  bool _dismissing = false; // guards complete() against re-entry (swipe + back)

  @override
  void initState() {
    super.initState();
    _deviceControls = ref.read(deviceControlsProvider);
    _engine = ref.read(playbackEngineProvider);
    // Drive the stale-frame cover: media_kit's texture is a singleton that keeps
    // showing the previous video's last frame until the newly-opened media
    // decodes. width→null on open, real width on first frame (see engine).
    _frameSub = _engine.hasVideoFrameStream.listen((has) {
      if (mounted) ref.read(videoFrameReadyProvider.notifier).state = has;
    });
    _resume = ref.read(resumeServiceProvider);
    _frames = ref.read(frameExtractorProvider);
    _audioOnly = ref.read(audioOnlyProvider.notifier);
    _miniThumb = ref.read(miniPlayerThumbnailProvider.notifier);
    _dismissApi = ref.read(playerDismissProvider.notifier);
    _pip = ref.read(pipControllerProvider);
    _pip.setCallbacks(PipCallbacks(
      onModeChanged: (inPip) {
        if (mounted) ref.read(pipModeProvider.notifier).state = inPip;
      },
      onPlay: () => _engine.play(),
      onPause: () => _engine.pause(),
      onSkip: (s) => ref.read(playerControllerProvider).skipBy(s),
    ));
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Force portrait on every fresh entry — a manual rotation left over
      // from a previous video must never carry over to the next one.
      ref.read(orientationProvider.notifier).reset();
      ref.read(orientationProvider.notifier).apply();
      _start();
    });
    _deviceControls.keepAwake(true);
    _deviceControls.setImmersive(true);
    // Intercept hardware volume keys natively so the OS volume panel is
    // suppressed inside the player — only Kivo's HUD shows. Disabled in
    // dispose() so the library keeps the normal OS panel.
    _deviceControls.setVolumeKeyInterception(true);
    // Listen to hardware volume key changes and drive Kivo's model + HUD.
    // The volumeGestureActiveProvider guard prevents clamping gesture-driven
    // boost (>100%) when the system-volume listener receives the echo of a
    // setSystemVolume call made during a vertical drag.
    _sysVolSub = _deviceControls.systemVolumeStream.listen((v) {
      if (!mounted) return;
      if (ref.read(volumeGestureActiveProvider)) return;
      // Never let the echo of our own max-system volume (set while boosting past
      // 100 via keys/gesture) knock the boosted value back down to 100.
      if (v >= 1.0 && ref.read(volumePercentProvider) > 100) return;
      ref.read(volumePercentProvider.notifier).state = (v * 100).clamp(0.0, 100.0);
      ref.read(hudProvider.notifier).show(HudKind.volume, v, '${(v * 100).round()}%');
    });
    // Hardware volume keys are forwarded from native (while intercepting) and
    // driven through the same setVolumePercent path the vertical drag uses, so
    // they reach the >100% boost and always show the HUD — even at the system
    // max, where the OS emits no volume-change event.
    _volKeySub = ref.read(volumeKeyStreamProvider).listen((e) {
      if (!mounted) return;
      final boost = ref.read(settingsProvider).volumeBoostMax.toDouble();
      final next = volumeKeyStep(ref.read(volumePercentProvider), e.dir, e.maxIndex, boost);
      ref.read(playerControllerProvider).setVolumePercent(next);
      ref.read(hudProvider.notifier).show(HudKind.volume, next / 100, '${next.round()}%');
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 4), (_) => _saveProgress());
    _dismissCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
      ..addListener(() {
        ref.read(dismissProvider.notifier).state = _dismissCtl.value;
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _dismissApi.state = PlayerDismissApi(
        complete: _completeDismiss,
        cancel: _cancelDismiss,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveProgress();
    }
  }

  Future<void> _start() async {
    final session = ref.read(currentVideoProvider);
    if (session == null) return;
    // Captured BEFORE the reset below: true only when this entry is an
    // expand-from-mini-bar for THIS SAME session (compared by resume key,
    // not just "was something minimized" — opening a DIFFERENT video while
    // one happens to be minimized must still do a normal fresh open). The
    // engine may already be further along than the resume store when
    // expanding the same session — the mini-bar's own play/pause button can
    // advance playback with nothing persisting that progress — so
    // re-opening would reseek to the stale saved position instead of
    // wherever it actually is now.
    final expandingFromMini = ref.read(playerMinimizedProvider) &&
        ref.read(minimizedSessionKeyProvider) == session.resumeKey;
    // Fresh entry must never inherit stale app-scoped overlay state from the
    // previous player route: a stranded dismiss progress, or a resume toast
    // still on screen when the user jumped to another video.
    ref.read(dismissProvider.notifier).state = 0;
    _dismissing = false;
    ref.read(resumePromptProvider.notifier).state = null;
    ref.read(restartRequestProvider.notifier).state = 0;
    ref.read(playerMinimizedProvider.notifier).state = false;
    ref.read(miniPlayerThumbnailProvider.notifier).state = null;
    ref.read(minimizedSessionKeyProvider.notifier).state = null;
    // Deterministically clear any PiP flag: a modeChanged(false) that arrived
    // after the previous screen was disposed would have been dropped by its
    // mounted-guard, leaving this app-scoped flag stuck true → overlays hidden.
    ref.read(pipModeProvider.notifier).state = false;
    // A fresh entry must never carry over a pending/confirmed autoplay from
    // whatever the previous session was doing.
    ref.read(autoplayPendingProvider.notifier).state = null;
    ref.read(autoplayConfirmProvider.notifier).state = false;
    ref.read(queueJumpProvider.notifier).state = null;
    await _openSession(session, expandingFromMini: expandingFromMini);
    _deviceControls.currentVolume().then((v) {
      if (mounted) ref.read(volumePercentProvider.notifier).state = (v * 100).clamp(0, 100);
    });
    final remembered = ref.read(rateProvider);
    ref.read(playerControllerProvider).setRate(
      ref.read(settingsProvider).rememberSpeed ? remembered : 1.0,
    );
  }

  Future<void> _openSession(VideoSession session, {required bool expandingFromMini}) async {
    final engine = ref.read(playbackEngineProvider);
    _resumeKey = session.resumeKey;
    ref.read(playedStoreProvider).markPlayed(_resumeKey!);
    // Seed the stale-frame cover BEFORE the Video widget is revealed: a fresh
    // open must cover until the new first frame (below); expanding the same
    // session shows its already-correct frame immediately. The frame stream
    // then flips it as the media decodes.
    ref.read(videoFrameReadyProvider.notifier).state = expandingFromMini;
    final c = engine.createVideoController();
    if (c is VideoController) {
      _controller = c;
      setState(() {});
    }
    if (!expandingFromMini) {
      final plan = planResume(
          _resume.positionFor(_resumeKey!), ref.read(settingsProvider).resumeBehavior);
      await engine.open(session.playbackPath, startAt: plan.startAt);
      if (plan.prompt != ResumePromptKind.none) {
        ref.read(resumePromptProvider.notifier).state =
            ResumePromptState(plan.prompt, plan.savedPosition);
      }
    }
    final settings = ref.read(settingsProvider);
    await engine.setSubtitleStyle(
      fontSize: settings.subtitleFontSize,
      textColorArgb: settings.subtitleTextColor,
      backgroundColorArgb: settings.subtitleBackgroundColor,
    );
    if (!expandingFromMini) {
      applyDefaultTracks(
          engine: engine, settings: settings, session: session,
          subtitleFinder: ref.read(subtitleFinderProvider));
    }
    _frames.prepare(session.playbackPath);
    _armPip();
  }

  void _onCompleted() {
    // Once minimized, the app-level AutoplayCoordinator owns completion. This
    // guard makes the two mutually exclusive even during the minimize→dispose
    // window (playerMinimized flips true a few frames before this listener is
    // torn down), so a completion landing mid-minimize can't double-advance.
    if (ref.read(playerMinimizedProvider)) return;
    // Re-entrancy guard: completedStream can emit `true` more than once, and
    // an advance-in-flight (or a pending countdown) must not be reprocessed —
    // otherwise a stray second event would peekNext() off the ALREADY-advanced
    // index and skip a video.
    if (_advancing || ref.read(autoplayPendingProvider) != null) return;
    final loopActive = ref.read(abLoopProvider)?.phase == AbLoopPhase.active;
    final sleepStop = sleepStopsHere(ref.read(sleepTimerProvider));
    final next = ref.read(currentVideoProvider.notifier).peekNext();
    final go = shouldAutoplay(
      enabled: ref.read(settingsProvider).autoplayNext,
      hasNext: next != null,
      loopActive: loopActive,
      sleepStopsHere: sleepStop,
    );
    if (!go) {
      // Sleep timer's N-episodes / episode mode reaching its stop: pause + end
      // the timer so the video rests at its end (matches the timer's intent).
      if (sleepStop && next != null && ref.read(settingsProvider).autoplayNext && !loopActive) {
        _engine.pause();
        ref.read(sleepTimerProvider.notifier).cancel();
      }
      return;
    }
    // Overlay only when the player is actually on-screen (resumed AND not in
    // the tiny PiP window, where the overlay is suppressed — pinning it there
    // would leave autoplay stuck with an invisible countdown). Otherwise
    // advance immediately.
    final onScreen = WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed &&
        !ref.read(pipModeProvider);
    if (onScreen) {
      ref.read(autoplayPendingProvider.notifier).state = next;
    } else {
      _advance(next!);
    }
  }

  Future<void> _advance(VideoSession next, {bool countAsAutoplay = true}) async {
    _advancing = true;
    ref.read(autoplayPendingProvider.notifier).state = null;
    ref.read(autoplayConfirmProvider.notifier).state = false;
    if (countAsAutoplay) ref.read(sleepTimerProvider.notifier).onAutoplayAdvance();
    ref.read(currentVideoProvider.notifier).advanceTo(next);
    try {
      await _openSession(next, expandingFromMini: false);
    } finally {
      _advancing = false;
    }
  }

  ({int width, int height}) get _pipSize => _engine.videoSize ?? (width: 16, height: 9);

  void _armPip() {
    // PiP-auto-on-Home is user-configurable: when off, keep PiP disarmed so
    // onUserLeaveHint (native) won't float the player when leaving to Home.
    if (!ref.read(settingsProvider).pipAutoOnHome) {
      _pip.disarm();
      return;
    }
    final playing = ref.read(playingProvider).value ?? false;
    _pip.arm(width: _pipSize.width, height: _pipSize.height, playing: playing);
  }

  Future<void> _saveProgress() async {
    final key = _resumeKey;
    if (key == null || _lastDuration == Duration.zero) return;
    // Use the cached service, never `ref` — this runs from dispose(), where
    // reading a provider throws "ref used after dispose" and silently drops
    // the save (the root cause of resume never persisting on back-exit).
    await _resume.record(key, _lastPosition, _lastDuration,
        DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _captureMiniPreview() async {
    try {
      final bytes = await _frames.frameAt(_lastPosition);
      // Cached notifier (never `ref` here): this can resolve after the widget
      // is unmounted — it runs fire-and-forget, off the pop's critical path.
      _miniThumb.state = bytes;
    } catch (_) {
      // Extraction can fail (e.g. no keyframe near this position); the
      // mini-bar falls back to a placeholder icon when the bytes are null.
    }
  }

  void _completeDismiss() {
    if (_dismissing) return;
    _dismissing = true;
    if (!_previewCaptured) _captureMiniPreview();
    _dismissCtl.value = ref.read(dismissProvider);
    _dismissCtl
        .animateTo(1.0, duration: Duration(milliseconds: dismissDurationMs(_dismissCtl.value)))
        .then((_) {
      if (!mounted) return;
      _engine.pause();
      _saveProgress();
      ref.read(minimizedSessionKeyProvider.notifier).state = _resumeKey;
      ref.read(playerMinimizedProvider.notifier).state = true;
      Navigator.of(context).pop(); // unconditional pop — does not re-enter PopScope
    });
  }

  void _cancelDismiss() {
    _dismissCtl.value = ref.read(dismissProvider);
    _dismissCtl.animateBack(0.0);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _sysVolSub?.cancel();
    _volKeySub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress(); // best-effort for in-app pop
    _engine.pause(); // stop audio when leaving the player (engine is a singleton)
    _audioOnly.disable(); // reset "Solo audio" so it never carries over to the next open
    _pip.disarm();
    _frames.release(); // release native frame-extractor resources (cached; never via ref)
    _deviceControls.setOrientation([DeviceOrientationLock.auto]);
    _deviceControls.keepAwake(false);
    _deviceControls.setImmersive(false);
    _deviceControls.resetBrightness();
    _deviceControls.setVolumeKeyInterception(false);
    _frameSub?.cancel();
    _dismissCtl.dispose();
    // Deferred: writing to a provider synchronously inside dispose() can hit
    // "Tried to modify a provider while the widget tree was building" when
    // this dispose runs as part of the same frame's tree finalization (e.g.
    // right after Navigator.pop() during the route's own exit-transition
    // teardown). A microtask runs after that frame settles; guard with
    // `mounted` (StateNotifier's, not State's) in case the ProviderContainer
    // itself was torn down first (e.g. test teardown disposing the container).
    final api = _dismissApi;
    final self = api.state;
    scheduleMicrotask(() {
      // Identity-guard: only clear OUR published API. If a new PlayerScreen
      // somehow published before this microtask runs, don't clobber its handle.
      if (api.mounted && identical(api.state, self)) api.state = null;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(positionProvider, (_, next) {
      next.whenData((d) => _lastPosition = d);
    });
    ref.listen(durationProvider, (_, next) {
      next.whenData((d) => _lastDuration = d);
    });
    ref.listen(playingProvider, (_, next) {
      final playing = next.value ?? false;
      _pip.updateState(width: _pipSize.width, height: _pipSize.height, playing: playing);
    });
    ref.listen<int>(restartRequestProvider, (prev, next) {
      if (next > 0) {
        ref.read(playerControllerProvider).seekTo(Duration.zero);
        if (_resumeKey != null) _resume.clear(_resumeKey!);
        _lastPosition = Duration.zero;
      }
    });
    // Capture the mini-player freeze frame EAGERLY, as soon as a dismiss drag
    // gets underway — so the (slow, native) frame extraction runs during the
    // ~300ms slide instead of blocking the pop. Fire once per drag; reset when
    // the player snaps back to fullscreen.
    ref.listen<double>(dismissProvider, (prev, next) {
      if (next >= 0.12 && !_previewCaptured) {
        _previewCaptured = true;
        _captureMiniPreview();
      } else if (next == 0) {
        _previewCaptured = false;
      }
    });
    ref.listen(completedProvider, (_, next) {
      if (next.value == true) _onCompleted();
    });
    ref.listen(queueJumpProvider, (_, index) {
      if (index == null) return;
      final s = ref.read(currentVideoProvider.notifier).sessionAt(index);
      ref.read(queueJumpProvider.notifier).state = null;
      if (s != null) _advance(s, countAsAutoplay: false);
    });
    ref.listen(audioOnlyProvider, (prev, on) {
      // "Solo audio" has no video — lock to portrait (the rotate control is
      // hidden while it's on, so this stays put until the user leaves the mode).
      if (on) {
        ref.read(orientationProvider.notifier).reset();
        ref.read(orientationProvider.notifier).apply();
      }
    });
    ref.listen(autoplayConfirmProvider, (_, next) {
      final pending = ref.read(autoplayPendingProvider);
      if (next && pending != null) _advance(pending);
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final api = ref.read(playerDismissProvider);
        if (api != null) {
          api.complete();
        } else {
          // 1-frame window before the API is registered: fall back to the
          // previous immediate minimize+pop.
          _engine.pause();
          _saveProgress();
          if (!_previewCaptured) _captureMiniPreview();
          ref.read(minimizedSessionKeyProvider.notifier).state = _resumeKey;
          ref.read(playerMinimizedProvider.notifier).state = true;
          Navigator.of(context).pop();
        }
      },
      // Transparent so the (non-opaque) player route lets the library paint
      // behind it; the black backdrop below fades in/out with the dismiss so
      // the swipe reveals the library instead of a black void.
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Consumer(
          builder: (context, ref, _) {
            final dismissProgress = ref.watch(dismissProvider);
            final scale = 1.0 - dismissProgress * 0.06;
            final opacity = 1.0 - dismissProgress * 0.4;
            // Slide the whole player down by progress × screen height.
            final screenHeight = MediaQuery.sizeOf(context).height;
            final offsetY = dismissProgress * screenHeight;
            final videoReady = ref.watch(videoFrameReadyProvider);
            final videoBox = Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: _controller == null
                  ? const CircularProgressIndicator()
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Video(
                          controller: _controller!,
                          controls: NoVideoControls, // Kivo draws its own controls; this also kills media_kit's buffering spinner
                          fit: boxFitFor(ref.watch(aspectModeProvider)),
                          // 3e: the widget's own lifecycle handler pauses on
                          // app-background by default, silently defeating
                          // background playback.
                          pauseUponEnteringBackgroundMode: false,
                        ),
                        // Cover the singleton texture's stale last-frame (the
                        // previous video) until the freshly-opened media decodes
                        // its first frame — otherwise it flashes during the open.
                        if (!videoReady) const ColoredBox(color: Colors.black),
                      ],
                    ),
            );
            return Stack(
              children: [
                // Full-screen black backdrop, fully opaque at rest and fading
                // out as the player is dragged down → the library shows behind.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1.0 - dismissProgress).clamp(0.0, 1.0),
                      child: const ColoredBox(color: Colors.black),
                    ),
                  ),
                ),
                Transform.translate(
              offset: Offset(0, offsetY),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Stack(
                    children: [
                      Positioned.fill(child: videoBox),
                      if (!ref.watch(pipModeProvider)) ...[
                        const Positioned.fill(child: PlayerGestures(child: SizedBox.expand())),
                        // Above gestures: only its "Ver video" pill is
                        // hit-testable; taps/drags elsewhere fall through.
                        const Positioned.fill(child: AudioOnlyView()),
                        const Positioned.fill(child: RippleOverlay()),
                        const Positioned.fill(child: ControlsOverlay()),
                        const Positioned.fill(child: InfoOverlay()),
                        const Positioned.fill(child: FlashOverlay()),
                        const Positioned.fill(child: HudOverlay()),
                        const Positioned.fill(child: GestureSeekPreview()),
                        const Positioned.fill(child: SpeedLadderOverlay()),
                        const Positioned.fill(child: ResumePrompt()),
                        const Positioned.fill(child: SleepWarningToast()),
                        const Positioned.fill(child: AutoplayOverlay()),
                      ],
                    ],
                  ),
                ),
              ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
