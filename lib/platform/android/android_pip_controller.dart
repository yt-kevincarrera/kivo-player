import 'package:flutter/services.dart';
import '../interfaces/pip_controller.dart';

class AndroidPipController implements PipController {
  static const _channel = MethodChannel('kivo/pip');
  PipCallbacks? _cb;

  AndroidPipController() {
    _channel.setMethodCallHandler((call) async {
      final cb = _cb;
      if (cb == null) return;
      switch (call.method) {
        case 'modeChanged':
          cb.onModeChanged((call.arguments as Map)['inPip'] as bool);
        case 'play':
          cb.onPlay();
        case 'pause':
          cb.onPause();
        case 'skip':
          cb.onSkip((call.arguments as Map)['seconds'] as int);
      }
    });
  }

  @override
  Future<bool> isSupported() async =>
      (await _channel.invokeMethod<bool>('isSupported')) ?? false;

  @override
  void setCallbacks(PipCallbacks cb) => _cb = cb;

  @override
  Future<void> arm({required int width, required int height, required bool playing}) =>
      _channel.invokeMethod('arm', {'width': width, 'height': height, 'playing': playing});

  @override
  Future<void> disarm() => _channel.invokeMethod('disarm');

  @override
  Future<void> enterNow() => _channel.invokeMethod('enterNow');

  @override
  Future<void> updateState({required int width, required int height, required bool playing}) =>
      _channel.invokeMethod('updateState', {'width': width, 'height': height, 'playing': playing});
}
