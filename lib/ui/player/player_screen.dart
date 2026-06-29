import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/device_controls_provider.dart';
import '../../platform/interfaces/device_controls.dart';
import '../../player/control/player_controller.dart';
import '../../player/engine/playback_provider.dart';
import '../../player/open/video_source.dart';
import 'controls/controls_overlay.dart';
import 'gestures/player_gestures.dart';
import 'hud/hud_overlay.dart';
import 'speed/speed_ladder_overlay.dart';
import 'state/aspect_state.dart';

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
  String? _path;
  late final DeviceControls _deviceControls;

  @override
  void initState() {
    super.initState();
    _deviceControls = ref.read(deviceControlsProvider);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    _deviceControls.setOrientation([DeviceOrientationLock.landscape]);
    _deviceControls.keepAwake(true);
    _deviceControls.setImmersive(true);
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
    _path = session.path;
    final engine = ref.read(playbackEngineProvider);
    final resume = ref.read(resumeServiceProvider);
    final startAt = resume.positionFor(session.path) ?? Duration.zero;

    final c = engine.createVideoController();
    if (c is VideoController) {
      _controller = c;
      setState(() {});
    }
    await engine.open(session.path, startAt: startAt);
    final remembered = ref.read(rateProvider);
    ref.read(playerControllerProvider).setRate(
      ref.read(settingsProvider).rememberSpeed ? remembered : 1.0,
    );
  }

  Future<void> _saveProgress() async {
    final path = _path;
    if (path == null || _lastDuration == Duration.zero) return;
    await ref.read(resumeServiceProvider).record(path, _lastPosition, _lastDuration);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress(); // best-effort for in-app pop
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
                  : Video(controller: _controller!, fit: boxFitFor(ref.watch(aspectModeProvider))),
            ),
          ),
          const Positioned.fill(child: PlayerGestures(child: SizedBox.expand())),
          const Positioned.fill(child: ControlsOverlay()),
          const Positioned.fill(child: HudOverlay()),
          const Positioned.fill(child: SpeedLadderOverlay()),
        ],
      ),
    );
  }
}
