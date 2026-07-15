import 'dart:convert';
import 'dart:io';
import 'update_info.dart';

abstract class UpdateChecker {
  /// Latest release, or null on network/parse error (never throws).
  Future<UpdateInfo?> fetchLatest();
}

class GithubUpdateChecker implements UpdateChecker {
  GithubUpdateChecker(this._primaryAbi);
  final Future<String> Function() _primaryAbi;

  static final Uri _endpoint = Uri.parse(
      'https://api.github.com/repos/yt-kevincarrera/kivo-player/releases/latest');

  @override
  Future<UpdateInfo?> fetchLatest() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(_endpoint);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'kivo-player');
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      if (tag.isEmpty) return null;
      final assets = ((json['assets'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      final abi = await _primaryAbi();
      final version = tag.startsWith('v') || tag.startsWith('V') ? tag.substring(1) : tag;
      return UpdateInfo(
        version: version,
        tagName: tag,
        apkUrl: pickApkAsset(assets, abi),
        releaseUrl: (json['html_url'] as String?) ?? '',
        notes: (json['body'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}
