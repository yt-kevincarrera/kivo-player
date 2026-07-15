import 'package:flutter/services.dart';
import '../interfaces/app_installer.dart';

class AndroidAppInstaller implements AppInstaller {
  static const MethodChannel _channel = MethodChannel('kivo/update');

  @override
  Future<String> appVersion() async =>
      (await _channel.invokeMethod<String>('getAppVersion')) ?? '';

  @override
  Future<String> primaryAbi() async =>
      (await _channel.invokeMethod<String>('primaryAbi')) ?? 'arm64-v8a';

  @override
  Future<InstallOutcome> downloadAndInstall(String url, String fileName) async {
    try {
      final s = await _channel.invokeMethod<String>(
          'downloadAndInstall', {'url': url, 'fileName': fileName});
      return switch (s) {
        'started' => InstallOutcome.started,
        'needsPermission' => InstallOutcome.needsPermission,
        _ => InstallOutcome.failed,
      };
    } catch (_) {
      return InstallOutcome.failed;
    }
  }

  @override
  Future<void> openUrl(String url) async {
    try {
      await _channel.invokeMethod<void>('openUrl', {'url': url});
    } catch (_) {/* fire-and-forget */}
  }
}
