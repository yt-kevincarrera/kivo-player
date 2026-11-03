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
  Future<String> deviceModel() async {
    try {
      return (await _channel.invokeMethod<String>('deviceModel')) ?? '';
    } catch (_) {
      return '';
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
  Future<UpdatePreview?> previewUpdate(
    String url, {
    String? manifestUrl,
  }) async {
    try {
      final preview = await _channel
          .invokeMapMethod<String, dynamic>('previewUpdate', {
            'url': url,
            if (manifestUrl != null) 'manifestUrl': manifestUrl,
          })
          .timeout(const Duration(seconds: 15));
      if (preview == null) return null;
      return UpdatePreview(
        bytes: _positiveBytes(preview['bytes']),
        fullBytes: _positiveBytes(preview['fullBytes']),
        partial: preview['partial'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  static int? _positiveBytes(Object? value) {
    if (value is! num ||
        !value.isFinite ||
        value <= 0 ||
        value != value.roundToDouble()) {
      return null;
    }
    return value.toInt();
  }

  @override
  Future<int> enqueueUpdate(
    String url,
    String fileName, {
    String? manifestUrl,
  }) async {
    try {
      return (await _channel.invokeMethod<int>('enqueueUpdate', {
            'url': url,
            'fileName': fileName,
            if (manifestUrl != null) 'manifestUrl': manifestUrl,
          })) ??
          -1;
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<PendingUpdate?> pendingUpdate() async {
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>(
        'pendingUpdate',
      );
      final id = (data?['id'] as num?)?.toInt();
      final version = data?['version'] as String?;
      return id != null && id >= 0 && version != null && version.isNotEmpty
          ? PendingUpdate(id, version)
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Native status includes confirmed pause reasons and a separate thermal
  /// observation. Pending downloads don't expose their exact blocking reason.
  @override
  Future<DownloadProgress> downloadStatus(int id) async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>(
        'downloadStatus',
        {'id': id},
      );
      if (m == null) return DownloadProgress.gone;
      final received = (m['received'] as num?)?.toInt() ?? 0;
      final total = (m['total'] as num?)?.toInt() ?? -1;
      return DownloadProgress(
        _stage(m['status'] as String?, m['reason'] as String?),
        received: received,
        total: total,
        partial: m['partial'] == true,
        fallback: m['fallback'] == true,
        deviceHot: m['status'] == 'pending' && m['deviceHot'] == true,
      );
    } catch (_) {
      return DownloadProgress.gone;
    }
  }

  static DownloadStage _stage(String? status, String? reason) =>
      switch (status) {
        'pending' => DownloadStage.pending,
        'running' => DownloadStage.running,
        'paused' => switch (reason) {
          'retry' => DownloadStage.pausedRetry,
          'network' => DownloadStage.pausedNetwork,
          'wifi' => DownloadStage.pausedWifi,
          _ => DownloadStage.pausedUnknown,
        },
        'done' => DownloadStage.done,
        'preparing' => DownloadStage.preparing,
        'failed' => DownloadStage.failed,
        _ => DownloadStage.gone,
      };

  @override
  Future<void> cancelDownload(int id) async {
    try {
      await _channel.invokeMethod<void>('cancelDownload', {'id': id});
    } catch (_) {
      /* the download is going away either way */
    }
  }

  @override
  Future<InstallOutcome> installDownload(int id) async {
    try {
      final s = await _channel.invokeMethod<String>('installDownload', {
        'id': id,
      });
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
  Future<bool> openUrl(String url) async {
    try {
      await _channel.invokeMethod<void>('openUrl', {'url': url});
      return true;
    } catch (_) {
      // ActivityNotFoundException surfaces as OPEN_FAILED: nothing to open it.
      return false;
    }
  }
}
