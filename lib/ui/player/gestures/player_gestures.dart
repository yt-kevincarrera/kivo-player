import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../platform/device_controls_provider.dart';
import '../../../player/control/gesture_math.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../state/controls_visibility.dart';
import '../state/hud_state.dart';

class PlayerGestures extends ConsumerStatefulWidget {
  final Widget child;
  const PlayerGestures({super.key, required this.child});
  @override
  ConsumerState<PlayerGestures> createState() => _PlayerGesturesState();
}

class _PlayerGesturesState extends ConsumerState<PlayerGestures> {
  double _lastTapDx = 0;
  double _width = 1, _height = 1;
  bool _leftSide = true;
  double _brightness = 0.5;
  double _volume01 = 0.5;
  Duration _seekStart = Duration.zero;
  double _seekAccum = 0;

  void _haptic() {
    if (ref.read(settingsProvider).hapticsOnGestures) HapticFeedback.lightImpact();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _onDoubleTap() {
    final zone = tapZoneOf(_lastTapDx / _width);
    final ctrl = ref.read(playerControllerProvider);
    final st = ref.read(settingsProvider);
    switch (zone) {
      case TapZone.left:
        ctrl.skipBy(-st.doubleTapSkipLeft);
        _haptic();
        ref.read(hudProvider.notifier).show(HudKind.seek, 0, '-${st.doubleTapSkipLeft}s');
      case TapZone.right:
        ctrl.skipBy(st.doubleTapSkipRight);
        _haptic();
        ref.read(hudProvider.notifier).show(HudKind.seek, 0, '+${st.doubleTapSkipRight}s');
      case TapZone.center:
        if (st.doubleTapCenterPause) {
          ctrl.togglePlayPause();
          _haptic();
        }
    }
  }

  void _onVerticalStart(DragStartDetails d) {
    _leftSide = d.localPosition.dx < _width / 2;
    _volume01 = (ref.read(volumePercentProvider) / 100).clamp(0.0, 1.0);
    ref.read(deviceControlsProvider).currentBrightness().then((b) => _brightness = b);
  }

  void _onVerticalUpdate(DragUpdateDetails d) {
    final st = ref.read(settingsProvider);
    final ctrl = ref.read(playerControllerProvider);
    if (_leftSide) {
      _brightness = dragValue(_brightness, d.delta.dy, _height, st.brightnessSensitivity);
      ctrl.setBrightness(_brightness);
      ref.read(hudProvider.notifier).show(HudKind.brightness, _brightness, '${(_brightness * 100).round()}%');
    } else {
      _volume01 = dragValue(_volume01, d.delta.dy, _height, st.volumeSensitivity);
      final percent = _volume01 * st.volumeBoostMax;
      ctrl.setVolumePercent(percent);
      ref.read(hudProvider.notifier).show(HudKind.volume, _volume01, '${percent.round()}%');
    }
  }

  void _onHorizontalStart(DragStartDetails d) {
    _seekStart = ref.read(positionProvider).value ?? Duration.zero;
    _seekAccum = 0;
  }

  void _onHorizontalUpdate(DragUpdateDetails d) {
    final st = ref.read(settingsProvider);
    if (!st.horizontalSeek) return;
    final total = ref.read(durationProvider).value ?? Duration.zero;
    _seekAccum += (d.delta.dx / _width) * 90 * st.seekSensitivity;
    final target = clampSeek(_seekStart, Duration(seconds: _seekAccum.round()), total);
    ref.read(playerControllerProvider).seekTo(target);
    ref.read(hudProvider.notifier).show(HudKind.seek, 0, _fmt(target));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        _height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(controlsVisibleProvider.notifier).toggle(),
          onDoubleTapDown: (d) => _lastTapDx = d.localPosition.dx,
          onDoubleTap: _onDoubleTap,
          onVerticalDragStart: _onVerticalStart,
          onVerticalDragUpdate: _onVerticalUpdate,
          onHorizontalDragStart: _onHorizontalStart,
          onHorizontalDragUpdate: _onHorizontalUpdate,
          child: widget.child,
        );
      },
    );
  }
}
