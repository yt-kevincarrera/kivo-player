import 'package:flutter/services.dart';
import '../interfaces/app_installer.dart';

class AndroidAppInstaller implements AppInstaller {
  static const MethodChannel _channel = MethodChannel('kivo/update');

  @override
  Future<String> appVersion() async {
    try {
      return (await _channel.invokeMethod<String>('getAppVersion')) ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<String> primaryAbi() async {
    try {
      return (await _channel.invokeMethod<String>('primaryAbi')) ?? 'arm64-v8a';
    } catch (_) {
      return 'arm64-v8a';
    }
  }

  @override
  Future<int> androidSdk() async {
    try {
      return (await _channel.invokeMethod<int>('androidSdk')) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<int> enqueueUpdate(String url, String fileName) async {
    try {
      return (await _channel.invokeMethod<int>(
              'enqueueUpdate', {'url': url, 'fileName': fileName})) ??
          -1;
    } catch (_) {
      return -1;
    }
  }

  /// The native side reports DownloadManager's raw status/reason ints; the
  /// mapping to Kivo's vocabulary lives here so the platform layer stays a
  /// thin passthrough and the enum has one owner.
  @override
  Future<DownloadProgress> downloadStatus(int id) async {
    try {
      final m = await _channel
          .invokeMapMethod<String, dynamic>('downloadStatus', {'id': id});
      if (m == null) return DownloadProgress.gone;
      final received = (m['received'] as num?)?.toInt() ?? 0;
      final total = (m['total'] as num?)?.toInt() ?? -1;
      return DownloadProgress(_stage(m['status'] as String?, m['reason'] as String?),
          received: received, total: total);
    } catch (_) {
      return DownloadProgress.gone;
    }
  }

  static DownloadStage _stage(String? status, String? reason) => switch (status) {
        'pending' => DownloadStage.pending,
        'running' => DownloadStage.running,
        'paused' =>
          reason == 'retry' ? DownloadStage.pausedRetry : DownloadStage.pausedNetwork,
        'done' => DownloadStage.done,
        'failed' => DownloadStage.failed,
        _ => DownloadStage.gone,
      };

  @override
  Future<void> cancelDownload(int id) async {
    try {
      await _channel.invokeMethod<void>('cancelDownload', {'id': id});
    } catch (_) {/* the download is going away either way */}
  }

  @override
  Future<InstallOutcome> installDownload(int id) async {
    try {
      final s = await _channel.invokeMethod<String>('installDownload', {'id': id});
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
