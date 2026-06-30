import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/device_controls_provider.dart';
import '../engine/playback_provider.dart';
import 'gesture_math.dart';

final volumePercentProvider = StateProvider<double>((ref) => 100);
final volumeGestureActiveProvider = StateProvider<bool>((ref) => false);
final rateProvider = StateProvider<double>((ref) => 1.0);

final playerControllerProvider = Provider<PlayerController>((ref) => PlayerController(ref));

class PlayerController {
  final Ref _ref;
  PlayerController(this._ref);

  void togglePlayPause() {
    final playing = _ref.read(playingProvider).value ?? false;
    final engine = _ref.read(playbackEngineProvider);
    playing ? engine.pause() : engine.play();
  }

  void skipBy(int seconds) {
    final pos = _ref.read(positionProvider).value ?? Duration.zero;
    final total = _ref.read(durationProvider).value ?? Duration.zero;
    seekTo(clampSeek(pos, Duration(seconds: seconds), total));
  }

  void seekTo(Duration p) => _ref.read(playbackEngineProvider).seek(p);

  double get currentRate => _ref.read(rateProvider);

  void setRate(double rate) {
    final max = _ref.read(settingsProvider).holdRightMax;
    final clamped = clampRate(round2(rate), 0.25, max);
    _ref.read(playbackEngineProvider).setRate(clamped);
    _ref.read(rateProvider.notifier).state = clamped;
  }

  double get currentVolumePercent => _ref.read(volumePercentProvider);

  void setVolumePercent(double percent) {
    final boost = _ref.read(settingsProvider).volumeBoostMax.toDouble();
    final v = percent.clamp(0.0, boost);
    final m = volumeMapping(v, boost);
    _ref.read(deviceControlsProvider).setSystemVolume(m.system01);
    _ref.read(playbackEngineProvider).setVolume(m.playerPercent);
    _ref.read(volumePercentProvider.notifier).state = v;
  }

  void setBrightness(double v01) =>
      _ref.read(deviceControlsProvider).setBrightness(v01.clamp(0.0, 1.0));
}
