import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../interfaces/launcher_bridge.dart';

class AndroidLauncherBridge implements LauncherBridge {
  AndroidLauncherBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openVideo') {
        final id = call.arguments as String?;
        if (id != null && id.isNotEmpty) _requests.add(id);
      }
      return null;
    });
  }

  static const _channel = MethodChannel('kivo/launch');
  final _requests = StreamController<String>.broadcast();

  @override
  Stream<String> get openRequests => _requests.stream;

  /// Best-effort: the shortcuts/widget showing something slightly stale is
  /// not worth an error in front of the user.
  @override
  Future<void> updateContinue(List<ContinueEntry> entries) async {
    try {
      await _channel.invokeMethod<void>(
          'updateContinue', [for (final e in entries) e.toMap()]);
    } catch (e) {
      debugPrint('AndroidLauncherBridge.updateContinue failed: $e');
    }
  }

  @override
  Future<String?> takeInitialOpenRequest() async {
    try {
      return await _channel.invokeMethod<String>('initialVideo');
    } catch (_) {
      return null;
    }
  }
}
