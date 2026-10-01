import 'dart:async';

import 'package:flutter/services.dart';

import '../interfaces/cast_platform.dart';

class AndroidCastPlatform implements CastPlatform {
  AndroidCastPlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopRequested') _stops.add(null);
      return null;
    });
  }

  static const _channel = MethodChannel('kivo/cast');
  final _stops = StreamController<void>.broadcast();

  @override
  Stream<void> get stopRequests => _stops.stream;

  @override
  Future<void> multicastLock(bool on) async {
    // Best effort: without it the search may simply find nothing.
    try {
      await _channel.invokeMethod<void>('multicastLock', {'on': on});
    } on PlatformException catch (_) {}
  }

  @override
  Future<ServedVideo> serve(String source) async {
    final m = await _channel
        .invokeMapMethod<String, Object?>('serve', {'source': source});
    return ServedVideo(
      port: m!['port']! as int,
      path: m['path']! as String,
      mime: m['mime']! as String,
      size: (m['size']! as num).toInt(),
    );
  }

  @override
  Future<void> stopServing() => _channel.invokeMethod<void>('stopServing');

  @override
  Future<void> keepAlive(bool on, {String device = ''}) =>
      _channel.invokeMethod<void>('keepAlive', {'on': on, 'device': device});
}
