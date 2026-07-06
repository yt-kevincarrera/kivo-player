import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A hardware volume-key press forwarded from the native side while the player
/// intercepts the keys: [dir] is +1 (up) / -1 (down) and [maxIndex] is the
/// device's STREAM_MUSIC step count (for one-step-per-press granularity).
typedef VolumeKeyEvent = ({int dir, int maxIndex});

/// Stream of hardware volume-key presses (only while interception is on — see
/// [DeviceControls.setVolumeKeyInterception]). The player drives its own
/// volume (including the >100% boost) from these instead of letting the keys
/// move the system volume, which caps at 100 and emits nothing at the max.
final volumeKeyStreamProvider = Provider<Stream<VolumeKeyEvent>>((ref) {
  const channel = MethodChannel('kivo/volume');
  final ctrl = StreamController<VolumeKeyEvent>.broadcast();
  channel.setMethodCallHandler((call) async {
    if (call.method == 'volumeKey') {
      final a = call.arguments as Map;
      ctrl.add((dir: a['dir'] as int, maxIndex: a['maxIndex'] as int));
    }
  });
  ref.onDispose(ctrl.close);
  return ctrl.stream;
});
