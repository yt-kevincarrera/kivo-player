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
import '../state/zoom_state.dart';
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
  double _rotateDy = 0; // accumulated vertical travel of a center-band drag
  bool _dismissHaptic = false; // fired the threshold-crossing tick once this drag
  double _topInset = 0;
  double _bottomInset = 0;

  // ── the drag state machine ───────────────────────────────────────────────
  // A pinch cannot coexist with two drag-axis recognizers (GestureDetector
  // throws), so ONE scale recognizer owns every drag and dispatches by pointer
  // count and dominant axis. `_intent` is null until the gesture has travelled
  // far enough to commit; see dragIntentFor.
  DragIntent? _intent;
  Offset _start = Offset.zero; // where the gesture began — dead zones are positional
  Offset _accum = Offset.zero; // travel since the start
  double _lastScale = 1.0; // previous ScaleUpdateDetails.scale, for the per-frame factor

  Size get _viewport => Size(_width, _height);

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

  void _onScaleStart(ScaleStartDetails d) {
    _start = d.localFocalPoint;
    _accum = Offset.zero;
    _lastScale = 1.0;
    _intent = null;
    _dismissHaptic = false;
    _decide(d.pointerCount);
  }

  /// Resolves the intent once enough is known and seeds whatever that intent
  /// needs. Idempotent: a decided intent is never re-decided.
  void _decide(int pointerCount) {
    if (_intent != null) return;
    final st = ref.read(settingsProvider);
    final next = dragIntentFor(
      pointerCount: pointerCount,
      pinchZoomEnabled: st.pinchZoom,
      zoomActive: ref.read(zoomProvider).active,
      start: _start,
      delta: _accum,
      viewport: _viewport,
      topInset: _topInset,
      bottomInset: _bottomInset,
      controlsVisible: ref.read(controlsVisibleProvider),
    );
    if (next == null) return; // not enough travel yet
    _intent = next;
    switch (next) {
      case DragIntent.brightness:
        ref.read(deviceControlsProvider).currentBrightness().then((b) => _brightness = b);
      case DragIntent.volume:
        _volPct = ref.read(volumePercentProvider);
        _volCap = _volPct < 100 ? 100.0 : st.volumeBoostMax.toDouble();
        // Mark the volume gesture active so the system-volume listener in
        // player_screen ignores hardware-key echo during the drag (preserves
        // boost >100).
        ref.read(volumeGestureActiveProvider.notifier).state = true;
      case DragIntent.seek:
        // The horizontalSeek setting is gated in the update below, not here:
        // seeding start state is a harmless no-op when seek is off.
        _seekStart = ref.read(positionProvider).value ?? Duration.zero;
        _seekAccum = 0;
      case DragIntent.rotate:
        _rotateDy = 0;
      case DragIntent.zoom:
      case DragIntent.pan:
      case DragIntent.dismiss:
      case DragIntent.none:
        break;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // A second finger takes over: abandon whatever one-finger gesture was
    // underway rather than letting the two fight over the same pointers.
    if (d.pointerCount >= 2 &&
        _intent != DragIntent.zoom &&
        ref.read(settingsProvider).pinchZoom) {
      _cancelIntent();
      _intent = DragIntent.zoom;
      _lastScale = d.scale;
    }
    _accum += d.focalPointDelta;
    if (_intent == null) {
      _decide(d.pointerCount);
      if (_intent == null) return;
    }
    if (_holding) return; // a hold-to-speed long-press owns this touch
    final st = ref.read(settingsProvider);
    final ctrl = ref.read(playerControllerProvider);
    final zoom = ref.read(zoomProvider.notifier);
    switch (_intent!) {
      case DragIntent.none:
        return;
      case DragIntent.zoom:
        final factor = _lastScale == 0 ? 1.0 : d.scale / _lastScale;
        _lastScale = d.scale;
        zoom.pinch(factor: factor, focal: d.localFocalPoint, viewport: _viewport);
        // Two fingers reframe as well, so a pinch can be aimed without lifting.
        zoom.panBy(d.focalPointDelta, _viewport);
      case DragIntent.pan:
        zoom.panBy(d.focalPointDelta, _viewport);
      case DragIntent.dismiss:
        // Drive dismiss progress live: clamp downward (0..1).
        final current = ref.read(dismissProvider);
        final fraction = (current + d.focalPointDelta.dy / _height).clamp(0.0, 1.0);
        ref.read(dismissProvider.notifier).state = fraction;
        if (!_dismissHaptic && fraction >= 0.25) {
          _dismissHaptic = true;
          _haptic(); // tick once when crossing the commit threshold
        }
      case DragIntent.rotate:
        _rotateDy += d.focalPointDelta.dy; // accumulate; the rotate fires on end
      case DragIntent.brightness:
        _brightness =
            dragValue(_brightness, d.focalPointDelta.dy, _height, st.brightnessSensitivity);
        ctrl.setBrightness(_brightness);
        ref.read(hudProvider.notifier).show(
            HudKind.brightness, _brightness, '${(_brightness * 100).round()}%');
      case DragIntent.volume:
        _volPct = dragVolumePercent(
            _volPct, d.focalPointDelta.dy, _height, st.volumeSensitivity, _volCap);
        ctrl.setVolumePercent(_volPct);
        ref.read(hudProvider.notifier).show(HudKind.volume, _volPct / 100, '${_volPct.round()}%');
      case DragIntent.seek:
        if (!st.horizontalSeek) return;
        final total = ref.read(durationProvider).value ?? Duration.zero;
        // Bar-like absolute mapping: accumulate raw horizontal travel and scale
        // a full-width drag at ms precision (× sensitivity).
        _seekAccum += d.focalPointDelta.dx;
        final target = horizontalSeekTarget(
            start: _seekStart, accumPx: _seekAccum, widthPx: _width,
            total: total, sensitivity: st.seekSensitivity);
        // Preview, don't live-seek: the video stays put while a centered card
        // shows the target frame + delta; the seek lands on release.
        ref.read(gestureSeekProvider.notifier).state = (target: target, from: _seekStart);
        ref.read(seekPreviewControllerProvider).request(target);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // Always clear the volume-gesture flag so hardware-key events resume
    // updating Kivo's volume model, whatever this drag turned out to be.
    ref.read(volumeGestureActiveProvider.notifier).state = false;
    final intent = _intent;
    _intent = null;
    switch (intent) {
      case DragIntent.rotate:
        final dy = _rotateDy;
        _rotateDy = 0;
        // Directional, not a toggle: swipe UP in portrait → landscape, DOWN in
        // landscape → portrait. Anything shorter than the threshold, or
        // pointing the other way, does nothing.
        final target = swipeRotateTarget(ref.read(orientationProvider), dy);
        if (target != null) {
          ref.read(orientationProvider.notifier).rotateTo(target);
          _haptic();
        }
      case DragIntent.dismiss:
        final progress = ref.read(dismissProvider);
        final api = ref.read(playerDismissProvider);
        if (dismissCommit(progress, d.velocity.pixelsPerSecond.dy)) {
          if (api != null) {
            api.complete();
          } else {
            // Defensive fallback if no PlayerScreen published the API.
            ref.read(dismissProvider.notifier).state = 0;
            Navigator.of(context).maybePop();
          }
        } else {
          _cancelDismiss(api);
        }
      case DragIntent.seek:
        final gesture = ref.read(gestureSeekProvider);
        if (gesture == null) return; // never engaged (dead zone / seek off)
        ref.read(playerControllerProvider).seekTo(gesture.target);
        // Hold the seek bar (if visible) at the target until real position
        // catches up, mirroring the bar's own release path.
        ref.read(pendingSeekProvider.notifier).state = gesture.target;
        ref.read(gestureSeekProvider.notifier).state = null; // hide the card
        // Drop the last frame so the next swipe doesn't flash the previous target.
        ref.read(seekPreviewFrameProvider.notifier).state = null;
        _haptic();
      case DragIntent.zoom:
        // One disk write per pinch (only in 'never' mode), not sixty.
        ref.read(zoomProvider.notifier).persistIfRemembered();
      case DragIntent.pan:
      case DragIntent.brightness:
      case DragIntent.volume:
      case DragIntent.none:
      case null:
        break;
    }
  }

  /// Unwinds a one-finger gesture that a second finger just stole.
  void _cancelIntent() {
    switch (_intent) {
      case DragIntent.dismiss:
        _cancelDismiss(ref.read(playerDismissProvider));
      case DragIntent.seek:
        ref.read(gestureSeekProvider.notifier).state = null;
        ref.read(seekPreviewFrameProvider.notifier).state = null;
      default:
        break;
    }
  }

  void _cancelDismiss(PlayerDismissApi? api) {
    if (api != null) {
      api.cancel();
    } else {
      ref.read(dismissProvider.notifier).state = 0;
    }
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (inVerticalDeadZone(
        d.localPosition.dy, _height, _topInset, _bottomInset, kVerticalDeadMargin)) {
      _holding = false;
      return;
    }
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
      final v = holdRightSpeedFor(
          _holdStartY, d.localPosition.dy, _holdStepPx, st.holdRightDetents, _holdBaseIndex);
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
    final v = holdRightSpeedFor(
        _holdStartY, d.localPosition.dy, _holdStepPx, st.holdRightDetents, _holdBaseIndex);
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
          // One scale recognizer owns pinch, pan AND every one-finger drag —
          // registering scale alongside both drag axes is a hard error.
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMove,
          onLongPressEnd: _onLongPressEnd,
          child: widget.child,
        );
      },
    );
  }
}
