import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/settings/kivo_settings.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/device_controls_provider.dart';
import '../../platform/interfaces/device_controls.dart';
import '../../player/control/player_controller.dart';
import '../../platform/frame_extractor_provider.dart';
import '../../platform/interfaces/frame_extractor.dart';
import '../../platform/subtitle_finder_provider.dart';
import '../../player/background/audio_only.dart';
import '../../player/engine/playback_engine.dart';
import '../../player/engine/playback_provider.dart';
import '../../player/library/played.dart';
import '../../player/open/video_source.dart';
import '../../player/resume/resume_plan.dart';
import '../../player/resume/resume_service.dart';
import '../../player/tracks/track_selection.dart';
import 'audio_only/audio_only_view.dart';
import 'controls/controls_overlay.dart';
import 'controls/flash_overlay.dart';
import 'controls/info_overlay.dart';
import 'controls/resume_prompt.dart';
import 'gestures/player_gestures.dart';
import 'gestures/ripple_overlay.dart';
import 'hud/hud_overlay.dart';
import 'sleep/sleep_warning_toast.dart';
import 'speed/speed_ladder_overlay.dart';
import 'state/aspect_state.dart';
import 'state/dismiss_state.dart';
import 'state/hud_state.dart';
import 'state/mini_player_state.dart';
import 'state/orientation_state.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  VideoController? _controller;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;
  String? _resumeKey;
  late final DeviceControls _deviceControls;
  late final PlaybackEngine _engine;
  late final ResumeService _resume;
  late final FrameExtractor _frames;
  late final AudioOnlyNotifier _audioOnly;
  StreamSubscription<double>? _sysVolSub;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _deviceControls = ref.read(deviceControlsProvider);
    _engine = ref.read(playbackEngineProvider);
    _resume = ref.read(resumeServiceProvider);
    _frames = ref.read(frameExtractorProvider);
    _audioOnly = ref.read(audioOnlyProvider.notifier);
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
      ref.read(volumePercentProvider.notifier).state = (v * 100).clamp(0.0, 100.0);
      ref.read(hudProvider.notifier).show(HudKind.volume, v, '${(v * 100).round()}%');
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 4), (_) => _saveProgress());
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
    ref.read(resumePromptProvider.notifier).state = null;
    ref.read(restartRequestProvider.notifier).state = 0;
    ref.read(playerMinimizedProvider.notifier).state = false;
    ref.read(miniPlayerThumbnailProvider.notifier).state = null;
    ref.read(minimizedSessionKeyProvider.notifier).state = null;
    final engine = ref.read(playbackEngineProvider);
    _resumeKey = session.resumeKey;
    ref.read(playedStoreProvider).markPlayed(_resumeKey!);

    final c = engine.createVideoController();
    if (c is VideoController) {
      _controller = c;
      setState(() {});
    }
    if (expandingFromMini) {
      // Reconnect to the already-open, already-playing session as-is — do
      // not reopen the file or seek.
    } else {
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
      _applyDefaultTracks(engine, settings, session);
    }
    _deviceControls.currentVolume().then((v) {
      if (mounted) ref.read(volumePercentProvider.notifier).state = (v * 100).clamp(0, 100);
    });
    _frames.prepare(session.playbackPath); // fire-and-forget; no await to keep UI responsive
    final remembered = ref.read(rateProvider);
    ref.read(playerControllerProvider).setRate(
      ref.read(settingsProvider).rememberSpeed ? remembered : 1.0,
    );
  }

  void _applyDefaultTracks(PlaybackEngine engine, KivoSettings settings, VideoSession session) {
    () async {
      final audioTracks = await engine.audioTracksStream.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => const <MediaTrack>[],
      );
      final audioPick = selectAudioTrack(
        tracks: audioTracks,
        preferredLanguage: settings.preferredAudioLanguage,
      );
      if (audioPick != null) await engine.setAudioTrack(audioPick.id);

      final subtitleTracks = await engine.subtitleTracksStream.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => const <MediaTrack>[],
      );
      final subtitlePick = selectSubtitleTrack(
        tracks: subtitleTracks,
        enabledByDefault: settings.subtitlesEnabledByDefault,
        preferredLanguage: settings.preferredSubtitleLanguage,
      );
      if (subtitlePick != null) {
        await engine.setSubtitleTrack(subtitlePick.id);
      } else if (settings.subtitlesEnabledByDefault &&
          settings.preferredSubtitleLanguage != null &&
          session.folder != null) {
        // No embedded track matched — fall back to an external subtitle file
        // sitting next to the video whose filename encodes the preferred
        // language (e.g. "Pelicula.es.srt").
        try {
          final finder = ref.read(subtitleFinderProvider);
          final externals = await finder.findNear(session.folder!);
          for (final ext in externals) {
            if (languageFromFilename(ext.displayName) ==
                settings.preferredSubtitleLanguage) {
              await engine.setExternalSubtitle(ext.uri, title: ext.displayName);
              break;
            }
          }
        } catch (_) {
          // Best-effort — native channel errors or an empty/unreadable
          // folder must never break playback start.
        }
      }
    }();
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
      if (mounted) ref.read(miniPlayerThumbnailProvider.notifier).state = bytes;
    } catch (_) {
      // Extraction can fail (e.g. no keyframe near this position); the
      // mini-bar falls back to a placeholder icon when the bytes are null.
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _sysVolSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress(); // best-effort for in-app pop
    _engine.pause(); // stop audio when leaving the player (engine is a singleton)
    _audioOnly.disable(); // reset "Solo audio" so it never carries over to the next open
    _frames.release(); // release native frame-extractor resources (cached; never via ref)
    _deviceControls.setOrientation([DeviceOrientationLock.auto]);
    _deviceControls.keepAwake(false);
    _deviceControls.setImmersive(false);
    _deviceControls.resetBrightness();
    _deviceControls.setVolumeKeyInterception(false);
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
    ref.listen<int>(restartRequestProvider, (prev, next) {
      if (next > 0) {
        ref.read(playerControllerProvider).seekTo(Duration.zero);
        if (_resumeKey != null) _resume.clear(_resumeKey!);
        _lastPosition = Duration.zero;
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        // Pause immediately — minimizing must never leave audio playing
        // through the (possibly slow) freeze-frame capture below. Relying
        // on dispose()'s pause alone would leave an audible gap.
        _engine.pause();
        await _saveProgress();
        await _captureMiniPreview();
        if (!mounted) return;
        ref.read(minimizedSessionKeyProvider.notifier).state = _resumeKey;
        ref.read(playerMinimizedProvider.notifier).state = true;
        navigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Consumer(
          builder: (context, ref, _) {
            final dismissProgress = ref.watch(dismissProvider);
            final heroTag = 'libhero-${ref.watch(currentVideoProvider)?.playbackPath ?? ''}';
            final scale = 1.0 - dismissProgress * 0.06;
            final opacity = 1.0 - dismissProgress * 0.4;
            // Slide the whole player down by progress × screen height.
            final screenHeight = MediaQuery.sizeOf(context).height;
            final offsetY = dismissProgress * screenHeight;
            return Transform.translate(
              offset: Offset(0, offsetY),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Hero(
                          // Pairs with the library tile's Hero (tagged by uri);
                          // a full-bleed black box so the thumbnail expands to the
                          // whole screen cleanly even before the video is ready.
                          tag: heroTag,
                          child: Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            child: _controller == null
                                ? const CircularProgressIndicator()
                                : Video(
                                    controller: _controller!,
                                    controls: NoVideoControls, // Kivo draws its own controls; this also kills media_kit's buffering spinner
                                    fit: boxFitFor(ref.watch(aspectModeProvider)),
                                    // 3e: the widget's own lifecycle handler pauses on
                                    // app-background by default, silently defeating
                                    // background playback.
                                    pauseUponEnteringBackgroundMode: false,
                                  ),
                          ),
                        ),
                      ),
                      const Positioned.fill(child: AudioOnlyView()),
                      const Positioned.fill(child: PlayerGestures(child: SizedBox.expand())),
                      const Positioned.fill(child: RippleOverlay()),
                      const Positioned.fill(child: ControlsOverlay()),
                      const Positioned.fill(child: InfoOverlay()),
                      const Positioned.fill(child: FlashOverlay()),
                      const Positioned.fill(child: HudOverlay()),
                      const Positioned.fill(child: SpeedLadderOverlay()),
                      const Positioned.fill(child: ResumePrompt()),
                      const Positioned.fill(child: SleepWarningToast()),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
