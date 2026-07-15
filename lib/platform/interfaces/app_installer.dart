enum InstallOutcome {
  started,          // download enqueued; installer will launch on completion
  needsPermission,  // user must allow "install unknown apps" first
  failed,           // couldn't start (caller should offer the browser fallback)
}

/// Reads the running app's version/ABI and drives APK download + install.
abstract class AppInstaller {
  Future<String> appVersion();   // BuildConfig.VERSION_NAME, e.g. "1.0.0"
  Future<String> primaryAbi();   // Build.SUPPORTED_ABIS[0], e.g. "arm64-v8a"
  Future<InstallOutcome> downloadAndInstall(String url, String fileName);
  Future<void> openUrl(String url);
}
