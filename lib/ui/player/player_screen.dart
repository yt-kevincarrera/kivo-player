import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/device_controls_provider.dart';
import '../../platform/interfaces/device_controls.dart';
import '../../player/control/player_controller.dart';
import '../../player/engine/playback_engine.dart';
import '../../player/engine/playback_provider.dart';
import '../../player/open/video_source.dart';
import '../../player/resume/resume_plan.dart';
import 'controls/controls_overlay.dart';
import 'controls/flash_overlay.dart';
import 'controls/info_overlay.dart';
import 'controls/resume_prompt.dart';
import 'gestures/player_gestures.dart';
import 'hud/hud_overlay.dart';
import 'speed/speed_ladder_overlay.dart';
import 'state/aspect_state.dart';
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

  @override
  void initState() {
    super.initState();
    _deviceControls = ref.read(deviceControlsProvider);
    _engine = ref.read(playbackEngineProvider);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(orientationProvider.notifier).apply();
      _start();
    });
    _deviceControls.keepAwake(true);
    _deviceControls.setImmersive(true);
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
    final engine = ref.read(playbackEngineProvider);
    _resumeKey = session.resumeKey;
    final resume = ref.read(resumeServiceProvider);
    final plan = planResume(
        resume.positionFor(_resumeKey!), ref.read(settingsProvider).resumeBehavior);

    final c = engine.createVideoController();
    if (c is VideoController) {
      _controller = c;
      setState(() {});
    }
    await engine.open(session.path, startAt: plan.startAt);
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
    await ref.read(resumeServiceProvider).record(key, _lastPosition, _lastDuration);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress(); // best-effort for in-app pop
    _engine.pause(); // stop audio when leaving the player (engine is a singleton)
    _deviceControls.setOrientation([DeviceOrientationLock.auto]);
    _deviceControls.keepAwake(false);
    _deviceControls.setImmersive(false);
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
      body: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: _controller == null
                  ? const CircularProgressIndicator()
                  : Video(
                      controller: _controller!,
                      controls: NoVideoControls, // Kivo draws its own controls; this also kills media_kit's buffering spinner
                      fit: boxFitFor(ref.watch(aspectModeProvider)),
                    ),
            ),
          ),
          const Positioned.fill(child: PlayerGestures(child: SizedBox.expand())),
          const Positioned.fill(child: ControlsOverlay()),
          const Positioned.fill(child: InfoOverlay()),
          const Positioned.fill(child: FlashOverlay()),
          const Positioned.fill(child: HudOverlay()),
          const Positioned.fill(child: SpeedLadderOverlay()),
          const Positioned.fill(child: ResumePrompt()),
        ],
      ),
    );
  }
}
