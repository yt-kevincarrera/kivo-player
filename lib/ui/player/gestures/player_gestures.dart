import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../platform/device_controls_provider.dart';
import '../../../player/control/gesture_math.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../state/controls_visibility.dart';
import '../state/dismiss_state.dart';
import '../state/hud_state.dart';
import '../state/lock_state.dart';
import '../state/orientation_state.dart';
import '../state/player_dismiss_state.dart';
import '../../../player/background/audio_only.dart';
import '../seek/seek_preview.dart';
import 'ripple_state.dart';
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
  double _preHoldRate = 1.0; // selected rate before a hold — restored on release
  double _holdStartY = 0;
  int _holdBaseIndex = 0;
  static const double _holdStepPx = 48.0;
  double _brightness = 0.5;
  double _volPct = 100;
  double _volCap = 100;
  Duration _seekStart = Duration.zero;
  double _seekAccum = 0;
  bool _vDead = false;
  bool _hDead = false;
  bool _isDismiss = false; // true when the current vertical drag is a dismiss gesture
  bool _isTopRotate = false; // true when the current vertical drag began in the top rotate strip
  double _rotateDy = 0; // accumulated vertical travel of a top-strip drag
  bool _dismissHaptic = false; // fired the threshold-crossing tick once this drag
  double _topInset = 0;
  double _bottomInset = 0;
  static const _deadMargin = 24.0;
  static const _lateralMargin = 38.0;
  // Top band reserved for swipe-down-to-rotate. Generous (not just the 24px
  // dead margin) so the gesture still registers after the ~18px touch slop
  // shifts the reported drag-start downward — and to match "from the top".
  static const _topRotateMargin = 90.0;

  bool _dead(double dy) =>
      inVerticalDeadZone(dy, _height, _topInset, _bottomInset, _deadMargin);

  void _haptic() {
    if (ref.read(settingsProvider).hapticsOnGestures) HapticFeedback.lightImpact();
  }

  void _onDoubleTap() {
    final zone = tapZoneOf(_lastTapDx / _width);
    final ctrl = ref.read(playerControllerProvider);
    final st = ref.read(settingsProvider);
    switch (zone) {
      case TapZone.left:
        ctrl.skipBy(-st.doubleTapSkipLeft);
        _haptic();
        ref.read(rippleControllerProvider).bump(left: true, seconds: st.doubleTapSkipLeft);
      case TapZone.right:
        ctrl.skipBy(st.doubleTapSkipRight);
        _haptic();
        ref.read(rippleControllerProvider).bump(left: false, seconds: st.doubleTapSkipRight);
      case TapZone.center:
        if (st.doubleTapCenterPause) {
          ctrl.togglePlayPause();
          _haptic();
        }
    }
  }

  void _onVerticalStart(DragStartDetails d) {
    final dx = d.localPosition.dx;
    final dy = d.localPosition.dy;
    // Top strip → swipe-down-to-rotate (discrete; fires on end). Checked first
    // so the top corners rotate rather than minimize.
    _isTopRotate = inTopRotateZone(dy, _topInset, _topRotateMargin);
    if (_isTopRotate) {
      _rotateDy = 0;
      return;
    }
    // Minimize now lives only on the lateral edges (the top strip rotates).
    _isDismiss = inLateralDeadZone(dx, _width, _lateralMargin);
    if (_isDismiss) {
      _dismissHaptic = false;
      return;
    }
    _vDead = _dead(dy);
    if (_vDead) return;
    if (_holding) return; // a hold-to-speed gesture owns this touch
    _leftSide = dx < _width / 2;
    _volPct = ref.read(volumePercentProvider);
    _volCap = _volPct < 100
        ? 100.0
        : ref.read(settingsProvider).volumeBoostMax.toDouble();
    ref.read(deviceControlsProvider).currentBrightness().then((b) => _brightness = b);
    if (!_leftSide) {
      // Mark volume gesture active so the system-volume listener in player_screen
      // ignores hardware-key echo events during the drag (preserves boost >100).
      ref.read(volumeGestureActiveProvider.notifier).state = true;
    }
  }

  void _onVerticalUpdate(DragUpdateDetails d) {
    if (_isTopRotate) {
      _rotateDy += d.delta.dy; // accumulate; the rotate fires on end
      return;
    }
    if (_isDismiss) {
      // Drive dismiss progress live: clamp downward (0..1).
      final current = ref.read(dismissProvider);
      final fraction = (current + d.delta.dy / _height).clamp(0.0, 1.0);
      ref.read(dismissProvider.notifier).state = fraction;
      if (!_dismissHaptic && fraction >= 0.25) {
        _dismissHaptic = true;
        _haptic(); // tick once when crossing the commit threshold
      }
      return;
    }
    if (_vDead) return;
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

  void _onVerticalEnd(DragEndDetails d) {
    // Always clear the volume-gesture flag so hardware-key events resume updating
    // Kivo's volume model (regardless of whether this was a volume or dismiss drag).
    ref.read(volumeGestureActiveProvider.notifier).state = false;
    if (_isTopRotate) {
      _isTopRotate = false;
      final dy = _rotateDy;
      _rotateDy = 0;
      // A downward swipe past the threshold rotates — but not in Solo audio,
      // which is locked to portrait (rotation disabled there).
      if (dy >= 48 && !ref.read(audioOnlyProvider)) {
        ref.read(orientationProvider.notifier).cycle();
        _haptic();
      }
      return;
    }
    if (!_isDismiss) return;
    _isDismiss = false;
    final progress = ref.read(dismissProvider);
    final velocityY = d.primaryVelocity ?? 0;
    final api = ref.read(playerDismissProvider);
    if (dismissCommit(progress, velocityY)) {
      if (api != null) {
        api.complete();
      } else {
        // Defensive fallback if no PlayerScreen published the API.
        ref.read(dismissProvider.notifier).state = 0;
        Navigator.of(context).maybePop();
      }
    } else {
      api?.cancel();
    }
  }

  void _onHorizontalStart(DragStartDetails d) {
    final dy = d.localPosition.dy;
    final dx = d.localPosition.dx;
    _hDead = _dead(dy) || inLateralDeadZone(dx, _width, _lateralMargin);
    // The horizontalSeek setting is gated in _onHorizontalUpdate, not here:
    // GestureDetector handlers can't be conditionally unregistered without a
    // rebuild, and seeding start state is a harmless no-op when seek is off.
    _seekStart = ref.read(positionProvider).value ?? Duration.zero;
    _seekAccum = 0;
  }

  void _onHorizontalUpdate(DragUpdateDetails d) {
    if (_hDead) return;
    if (_holding) return; // don't scrub while holding to speed
    final st = ref.read(settingsProvider);
    if (!st.horizontalSeek) return;
    final total = ref.read(durationProvider).value ?? Duration.zero;
    // Bar-like absolute mapping: accumulate raw horizontal travel and scale a
    // full-width drag to the whole video at ms precision (× sensitivity) —
    // instead of a fixed 90s-per-screen nudge rounded to whole seconds.
    _seekAccum += d.delta.dx;
    final target = horizontalSeekTarget(
        start: _seekStart, accumPx: _seekAccum, widthPx: _width,
        total: total, sensitivity: st.seekSensitivity);
    // Preview, don't live-seek: the video stays put while a centered card shows
    // the target frame + delta; the seek lands on release (_onHorizontalEnd).
    ref.read(gestureSeekProvider.notifier).state = (target: target, from: _seekStart);
    ref.read(seekPreviewControllerProvider).request(target);
  }

  void _onHorizontalEnd(DragEndDetails d) {
    final gesture = ref.read(gestureSeekProvider);
    if (gesture == null) return; // gesture never engaged (dead zone / seek off)
    final target = gesture.target;
    ref.read(playerControllerProvider).seekTo(target);
    // Hold the seek bar (if visible) at the target until real position catches
    // up, mirroring the bar's own release path.
    ref.read(pendingSeekProvider.notifier).state = target;
    ref.read(gestureSeekProvider.notifier).state = null; // hide the card
    // Drop the last frame so the next swipe doesn't flash the previous target.
    ref.read(seekPreviewFrameProvider.notifier).state = null;
    _haptic();
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (_dead(d.localPosition.dy)) { _holding = false; return; }
    final st = ref.read(settingsProvider);
    final ctrl = ref.read(playerControllerProvider);
    _holding = true;
    // Remember the user's selected rate so releasing restores IT, not a
    // hardcoded 1x (setRate below overwrites rateProvider with the hold speed).
    _preHoldRate = ref.read(rateProvider);
    _holdLeft = d.localPosition.dx < _width / 2;
    if (_holdLeft) {
      ctrl.setRate(st.holdLeftSpeed);
      ref.read(holdSpeedProvider.notifier).state = st.holdLeftSpeed;
      ref.read(holdSpeedIsLadderProvider.notifier).state = false;
      _lastHoldSpeed = st.holdLeftSpeed;
    } else {
      _holdStartY = d.localPosition.dy;
      _holdBaseIndex = defaultHoldRightIndex(st.holdRightDetents);
      final v = holdRightSpeedFor(_holdStartY, d.localPosition.dy, _holdStepPx, st.holdRightDetents, _holdBaseIndex);
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
    final v = holdRightSpeedFor(_holdStartY, d.localPosition.dy, _holdStepPx, st.holdRightDetents, _holdBaseIndex);
    ref.read(playerControllerProvider).setRate(v);
    ref.read(holdSpeedProvider.notifier).state = v;
    if (v != _lastHoldSpeed) { _haptic(); _lastHoldSpeed = v; }
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    // A long-press that began in a dead zone never engaged (_holding stays
    // false); Flutter still delivers End, so bail before touching the rate.
    if (!_holding) return;
    final st = ref.read(settingsProvider);
    if (_holdLeft || st.holdRightReleaseToNormal) {
      // Restore the rate that was selected before the hold (e.g. 1.5x), not 1x.
      ref.read(playerControllerProvider).setRate(_preHoldRate);
    }
    ref.read(holdSpeedProvider.notifier).state = null;
    ref.read(holdSpeedIsLadderProvider.notifier).state = false;
    _lastHoldSpeed = null;
    _holding = false;
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(lockProvider);
    final mq = MediaQuery.of(context);
    _topInset = mq.viewPadding.top;
    _bottomInset = mq.viewPadding.bottom;
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
          onVerticalDragEnd: _onVerticalEnd,
          onHorizontalDragStart: _onHorizontalStart,
          onHorizontalDragUpdate: _onHorizontalUpdate,
          onHorizontalDragEnd: _onHorizontalEnd,
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMove,
          onLongPressEnd: _onLongPressEnd,
          child: widget.child,
        );
      },
    );
  }
}
