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
import '../state/lock_state.dart';
import '../speed/speed_ladder_overlay.dart';

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
  bool _holdLeft = false;
  bool _holding = false; // true while a hold-to-speed long-press is active
  double? _lastHoldSpeed;
  double _brightness = 0.5;
  double _volPct = 100;
  double _volCap = 100;
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
        ref.read(hudProvider.notifier).show(HudKind.seek, -1.0, '-${st.doubleTapSkipLeft}s');
      case TapZone.right:
        ctrl.skipBy(st.doubleTapSkipRight);
        _haptic();
        ref.read(hudProvider.notifier).show(HudKind.seek, 1.0, '+${st.doubleTapSkipRight}s');
      case TapZone.center:
        if (st.doubleTapCenterPause) {
          ctrl.togglePlayPause();
          _haptic();
        }
    }
  }

  void _onVerticalStart(DragStartDetails d) {
    if (_holding) return; // a hold-to-speed gesture owns this touch
    _leftSide = d.localPosition.dx < _width / 2;
    _volPct = ref.read(volumePercentProvider);
    _volCap = _volPct < 100
        ? 100.0
        : ref.read(settingsProvider).volumeBoostMax.toDouble();
    ref.read(deviceControlsProvider).currentBrightness().then((b) => _brightness = b);
  }

  void _onVerticalUpdate(DragUpdateDetails d) {
    if (_holding) return; // don't change brightness/volume while holding to speed
    final st = ref.read(settingsProvider);
    final ctrl = ref.read(playerControllerProvider);
    if (_leftSide) {
      _brightness = dragValue(_brightness, d.delta.dy, _height, st.brightnessSensitivity);
      ctrl.setBrightness(_brightness);
      ref.read(hudProvider.notifier).show(HudKind.brightness, _brightness, '${(_brightness * 100).round()}%');
    } else {
      _volPct = dragVolumePercent(_volPct, d.delta.dy, _height, st.volumeSensitivity, _volCap);
      ctrl.setVolumePercent(_volPct);
      ref.read(hudProvider.notifier).show(HudKind.volume, _volPct / 100, '${_volPct.round()}%');
    }
  }

  void _onHorizontalStart(DragStartDetails d) {
    // The horizontalSeek setting is gated in _onHorizontalUpdate, not here:
    // GestureDetector handlers can't be conditionally unregistered without a
    // rebuild, and seeding start state is a harmless no-op when seek is off.
    _seekStart = ref.read(positionProvider).value ?? Duration.zero;
    _seekAccum = 0;
  }

  void _onHorizontalUpdate(DragUpdateDetails d) {
    if (_holding) return; // don't scrub while holding to speed
    final st = ref.read(settingsProvider);
    if (!st.horizontalSeek) return;
    final total = ref.read(durationProvider).value ?? Duration.zero;
    _seekAccum += (d.delta.dx / _width) * 90 * st.seekSensitivity;
    final target = clampSeek(_seekStart, Duration(seconds: _seekAccum.round()), total);
    ref.read(playerControllerProvider).seekTo(target);
    final delta = target - _seekStart;
    final label = delta == Duration.zero
        ? _fmt(target)
        : '${_fmt(target)}  (${delta.isNegative ? '-' : '+'}${_fmt(delta.abs())})';
    ref.read(hudProvider.notifier).show(HudKind.seek, delta.isNegative ? -1.0 : 1.0, label);
  }

  void _onLongPressStart(LongPressStartDetails d) {
    final st = ref.read(settingsProvider);
    final ctrl = ref.read(playerControllerProvider);
    _holding = true;
    _holdLeft = d.localPosition.dx < _width / 2;
    if (_holdLeft) {
      ctrl.setRate(st.holdLeftSpeed);
      ref.read(holdSpeedProvider.notifier).state = st.holdLeftSpeed;
      ref.read(holdSpeedIsLadderProvider.notifier).state = false;
      _lastHoldSpeed = st.holdLeftSpeed;
    } else {
      final v = holdRightSpeedFor(d.localPosition.dy, _height, st.holdRightDetents);
      ctrl.setRate(v);
      ref.read(holdSpeedProvider.notifier).state = v;
      ref.read(holdSpeedIsLadderProvider.notifier).state = true;
      _lastHoldSpeed = v;
    }
    _haptic();
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (_holdLeft) return;
    final st = ref.read(settingsProvider);
    final v = holdRightSpeedFor(d.localPosition.dy, _height, st.holdRightDetents);
    ref.read(playerControllerProvider).setRate(v);
    ref.read(holdSpeedProvider.notifier).state = v;
    if (v != _lastHoldSpeed) {
      _haptic();
      _lastHoldSpeed = v;
    }
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    final st = ref.read(settingsProvider);
    if (_holdLeft || st.holdRightReleaseToNormal) {
      ref.read(playerControllerProvider).setRate(1.0);
    }
    ref.read(holdSpeedProvider.notifier).state = null;
    ref.read(holdSpeedIsLadderProvider.notifier).state = false;
    _lastHoldSpeed = null;
    _holding = false;
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(lockProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        _height = constraints.maxHeight;
        if (locked) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(controlsVisibleProvider.notifier).toggle(),
            child: widget.child,
          );
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(controlsVisibleProvider.notifier).toggle(),
          onDoubleTapDown: (d) => _lastTapDx = d.localPosition.dx,
          onDoubleTap: _onDoubleTap,
          onVerticalDragStart: _onVerticalStart,
          onVerticalDragUpdate: _onVerticalUpdate,
          onHorizontalDragStart: _onHorizontalStart,
          onHorizontalDragUpdate: _onHorizontalUpdate,
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMove,
          onLongPressEnd: _onLongPressEnd,
          child: widget.child,
        );
      },
    );
  }
}
