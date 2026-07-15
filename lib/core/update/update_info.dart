/// The latest release, as parsed from GitHub.
class UpdateInfo {
  final String version;   // e.g. "1.0.1" (tag without the leading v)
  final String tagName;   // e.g. "v1.0.1"
  final String? apkUrl;   // direct download for this device's ABI, or null
  final String releaseUrl; // html_url — the release page (browser fallback)
  final String notes;     // release body/changelog
  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.apkUrl,
    required this.releaseUrl,
    required this.notes,
  });
}

/// Chooses the best APK download URL for [abi] from a GitHub release's assets.
String? pickApkAsset(List<Map<String, dynamic>> assets, String abi) {
  String? url(bool Function(String name) match) {
    for (final a in assets) {
      final name = (a['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk') && match(name.toLowerCase())) {
        return a['browser_download_url'] as String?;
      }
    }
    return null;
  }

  return url((n) => n.contains(abi.toLowerCase())) ??
      url((n) => n.contains('arm64-v8a')) ??
      url((_) => true);
}
