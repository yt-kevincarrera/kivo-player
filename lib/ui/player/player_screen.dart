import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/device_controls_provider.dart';
import '../../platform/interfaces/device_controls.dart';
import '../../player/control/player_controller.dart';
import '../../platform/frame_extractor_provider.dart';
import '../../platform/interfaces/frame_extractor.dart';
import '../../player/engine/playback_engine.dart';
import '../../player/engine/playback_provider.dart';
import '../../player/open/video_source.dart';
import '../../player/resume/resume_plan.dart';
import '../../player/resume/resume_service.dart';
import 'controls/controls_overlay.dart';
import 'controls/flash_overlay.dart';
import 'controls/info_overlay.dart';
import 'controls/resume_prompt.dart';
import 'gestures/player_gestures.dart';
import 'gestures/ripple_overlay.dart';
import 'hud/hud_overlay.dart';
import 'speed/speed_ladder_overlay.dart';
import 'state/aspect_state.dart';
import 'state/dismiss_state.dart';
import 'state/hud_state.dart';
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
  StreamSubscription<double>? _sysVolSub;

  @override
  void initState() {
    super.initState();
    _deviceControls = ref.read(deviceControlsProvider);
    _engine = ref.read(playbackEngineProvider);
    _resume = ref.read(resumeServiceProvider);
    _frames = ref.read(frameExtractorProvider);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(orientationProvider.notifier).apply();
      _start();
    });
    _deviceControls.keepAwake(true);
    _deviceControls.setImmersive(true);
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveProgress();
    }
    if (state == AppLifecycleState.paused) {
      _engine.pause(); // no background playback in Hito 1
    }
  }

  Future<void> _start() async {
    final session = ref.read(currentVideoProvider);
    if (session == null) return;
    // Fresh entry must never inherit stale app-scoped overlay state from the
    // previous player route: a stranded dismiss progress, or a resume toast
    // still on screen when the user jumped to another video.
    ref.read(dismissProvider.notifier).state = 0;
    ref.read(resumePromptProvider.notifier).state = null;
    final engine = ref.read(playbackEngineProvider);
    _resumeKey = session.resumeKey;
    final plan = planResume(
        _resume.positionFor(_resumeKey!), ref.read(settingsProvider).resumeBehavior);

    final c = engine.createVideoController();
    if (c is VideoController) {
      _controller = c;
      setState(() {});
    }
    await engine.open(session.playbackPath, startAt: plan.startAt);
    _deviceControls.currentVolume().then((v) {
      if (mounted) ref.read(volumePercentProvider.notifier).state = (v * 100).clamp(0, 100);
    });
    _frames.prepare(session.playbackPath); // fire-and-forget; no await to keep UI responsive
    final remembered = ref.read(rateProvider);
    ref.read(playerControllerProvider).setRate(
      ref.read(settingsProvider).rememberSpeed ? remembered : 1.0,
    );
    if (plan.prompt != ResumePromptKind.none) {
      ref.read(resumePromptProvider.notifier).state =
          ResumePromptState(plan.prompt, plan.savedPosition);
    }
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

  @override
  void dispose() {
    _sysVolSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress(); // best-effort for in-app pop
    _engine.pause(); // stop audio when leaving the player (engine is a singleton)
    _frames.release(); // release native frame-extractor resources (cached; never via ref)
    _deviceControls.setOrientation([DeviceOrientationLock.auto]);
    _deviceControls.keepAwake(false);
    _deviceControls.setImmersive(false);
    _deviceControls.resetBrightness();
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

    return Scaffold(
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
                                ),
                        ),
                      ),
                    ),
                    const Positioned.fill(child: PlayerGestures(child: SizedBox.expand())),
                    const Positioned.fill(child: RippleOverlay()),
                    const Positioned.fill(child: ControlsOverlay()),
                    const Positioned.fill(child: InfoOverlay()),
                    const Positioned.fill(child: FlashOverlay()),
                    const Positioned.fill(child: HudOverlay()),
                    const Positioned.fill(child: SpeedLadderOverlay()),
                    const Positioned.fill(child: ResumePrompt()),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
