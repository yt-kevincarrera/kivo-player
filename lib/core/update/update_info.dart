/// The latest release, as parsed from GitHub.
class UpdateInfo {
  final String version; // e.g. "1.0.1" (tag without the leading v)
  final String tagName; // e.g. "v1.0.1"
  final String? apkUrl; // direct download for this device's ABI, or null
  final String releaseUrl; // html_url — the release page (browser fallback)
  final String notes; // release body/changelog
  final String? manifestUrl; // optional verified delta/full artifact metadata
  final int? apkSizeBytes; // full APK size, when supplied by GitHub
  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.apkUrl,
    required this.releaseUrl,
    required this.notes,
    this.manifestUrl,
    this.apkSizeBytes,
  });
}

const updateManifestName = 'kivo-update-v1.json';

String? pickUpdateManifest(List<Map<String, dynamic>> assets) {
  for (final asset in assets) {
    if (asset['name'] == updateManifestName) {
      return asset['browser_download_url'] as String?;
    }
  }
  return null;
}

/// Chooses the best APK download URL for [abi] from a GitHub release's assets.
String? pickApkAsset(List<Map<String, dynamic>> assets, String abi) {
  return pickApkAssetInfo(assets, abi)?.url;
}

/// Keeps the full size paired with the exact APK selected for this device.
({String url, int? sizeBytes})? pickApkAssetInfo(
  List<Map<String, dynamic>> assets,
  String abi,
) {
  ({String url, int? sizeBytes})? asset(bool Function(String name) match) {
    for (final a in assets) {
      final name = (a['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk') && match(name.toLowerCase())) {
        final url = a['browser_download_url'];
        if (url is! String || url.isEmpty) continue;
        final size = a['size'];
        return (url: url, sizeBytes: size is int && size > 0 ? size : null);
      }
    }
    return null;
  }

  return asset((n) => n.contains(abi.toLowerCase())) ??
      asset((n) => n.contains('arm64-v8a')) ??
      asset((_) => true);
}
