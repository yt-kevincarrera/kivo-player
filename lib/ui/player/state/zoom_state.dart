import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/zoom_math.dart';

/// Pinch-zoom of the video surface. [offset] is always pre-clamped, so an
/// out-of-bounds state cannot exist — every mutation goes through zoom_math.
class ZoomState {
  final double scale;
  final Offset offset;
  const ZoomState({this.scale = kZoomMin, this.offset = Offset.zero});

  /// Slightly above 1 so float dust from a pinch that settled back at 1x does
  /// not keep the chip on screen.
  bool get active => scale > 1.001;
}

class ZoomNotifier extends Notifier<ZoomState> {
  @override
  ZoomState build() {
    final s = ref.read(settingsProvider);
    if (s.zoomResetMode != 'never') return const ZoomState();
    // The remembered FACTOR is restored; the framing is not — an offset chosen
    // for another file means nothing here.
    return ZoomState(scale: s.zoomRemembered.clamp(kZoomMin, s.zoomMax));
  }

  void pinch({required double factor, required Offset focal, required Size viewport}) {
    final r = zoomAt(
      scale: state.scale,
      offset: state.offset,
      factor: factor,
      focal: focal,
      viewport: viewport,
      max: ref.read(settingsProvider).zoomMax,
    );
    state = ZoomState(scale: r.scale, offset: r.offset);
  }

  void panBy(Offset delta, Size viewport) {
    if (!state.active) return;
    state = ZoomState(
      scale: state.scale,
      offset: clampZoomOffset(state.offset + delta, state.scale, viewport),
    );
  }

  /// The chip. Unconditional — it is the only thing that clears the zoom in
  /// 'never' mode.
  void reset() {
    state = const ZoomState();
    _persist(kZoomMin);
  }

  void onVideoChanged() {
    if (ref.read(settingsProvider).zoomResetMode == 'video') state = const ZoomState();
  }

  void onPlayerExit() {
    if (ref.read(settingsProvider).zoomResetMode != 'never') state = const ZoomState();
  }

  /// Call when a pinch SETTLES (gesture end), not per frame — one disk write per
  /// pinch instead of sixty.
  void persistIfRemembered() => _persist(state.scale);

  void _persist(double scale) {
    final s = ref.read(settingsProvider);
    if (s.zoomResetMode != 'never' || s.zoomRemembered == scale) return;
    ref.read(settingsProvider.notifier).set(s.copyWith(zoomRemembered: scale));
  }
}

final zoomProvider = NotifierProvider<ZoomNotifier, ZoomState>(ZoomNotifier.new);
