enum InstallOutcome {
  started,          // the system installer was launched
  needsPermission,  // user must allow "install unknown apps" first
  failed,           // couldn't start (caller should offer the browser fallback)
}

/// Where a queued download currently is.
///
/// The paused variants are the whole reason this enum exists: DownloadManager
/// defers downloads under Doze or on a metered network and, before this, the
/// app showed nothing at all — a deferred download and a broken one looked
/// identical. Surfacing the reason turns a silent freeze into a sentence.
enum DownloadStage {
  pending,        // queued, not a byte transferred yet
  running,
  pausedNetwork,  // waiting for connectivity, or for Wi-Fi on a metered link
  pausedRetry,    // transient failure; the system will retry on its own
  done,
  failed,
  gone,           // no such download — cleared by the system or by the user
}

class DownloadProgress {
  const DownloadProgress(this.stage, {this.received = 0, this.total = -1});

  final DownloadStage stage;
  final int received;

  /// Bytes expected, or -1 when the server sent no Content-Length.
  final int total;

  static const gone = DownloadProgress(DownloadStage.gone);

  /// null when [total] is unknown — the UI shows an indeterminate bar.
  double? get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  bool get isPaused =>
      stage == DownloadStage.pausedNetwork || stage == DownloadStage.pausedRetry;

  bool get isSettled =>
      stage == DownloadStage.done ||
      stage == DownloadStage.failed ||
      stage == DownloadStage.gone;

  @override
  bool operator ==(Object other) =>
      other is DownloadProgress &&
      other.stage == stage &&
      other.received == received &&
      other.total == total;

  @override
  int get hashCode => Object.hash(stage, received, total);
}

/// Reads the running app's version/ABI and drives APK download + install.
///
/// Download and install are deliberately separate: the download outlives the
/// app (DownloadManager owns it), while installing is an explicit user action
/// taken from inside Kivo.
abstract class AppInstaller {
  Future<String> appVersion();   // BuildConfig.VERSION_NAME, e.g. "1.0.0"
  Future<String> primaryAbi();   // Build.SUPPORTED_ABIS[0], e.g. "arm64-v8a"
  Future<int> androidSdk();      // Build.VERSION.SDK_INT — logged with each failure

  /// Queues the APK and returns the download id, or -1 if it couldn't start.
  Future<int> enqueueUpdate(String url, String fileName);

  Future<DownloadProgress> downloadStatus(int id);

  /// Removes the download and its partial file. Safe on an unknown id.
  Future<void> cancelDownload(int id);

  /// Hands the finished APK to the system installer.
  Future<InstallOutcome> installDownload(int id);

  Future<void> openUrl(String url);
}
