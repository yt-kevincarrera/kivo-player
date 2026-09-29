import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../errors/error_log.dart';
import '../errors/kivo_failure.dart';
import 'update_info.dart';

abstract class UpdateChecker {
  /// Latest release, or null on network/parse error (never throws).
  Future<UpdateInfo?> fetchLatest();
}

/// A non-200 from GitHub, with what it said about the rate limit — the usual
/// reason: the API allows 60 requests an hour per public IP, and a carrier
/// that puts many phones behind one IP exhausts that on its own.
class _HttpStatus implements Exception {
  _HttpStatus(this.url, this.status, this.headers);
  final Uri url;
  final int status;
  final HttpHeaders headers;

  @override
  String toString() {
    final remaining = headers.value('x-ratelimit-remaining');
    final reset = headers.value('x-ratelimit-reset');
    return 'HTTP $status from $url'
        '${remaining == null ? '' : ' (rate limit remaining $remaining, reset $reset)'}';
  }
}

class GithubUpdateChecker implements UpdateChecker {
  GithubUpdateChecker(
    this._primaryAbi, {
    ErrorLog? log,
    Uri? apiEndpoint,
    Uri? latestPage,
  })  : _log = log,
        _api = apiEndpoint ?? _defaultApi,
        _page = latestPage ?? _defaultPage;

  final Future<String> Function() _primaryAbi;

  /// Optional so existing tests can build a checker without a log.
  final ErrorLog? _log;
  final Uri _api;
  final Uri _page;

  static final Uri _defaultApi = Uri.parse(
      'https://api.github.com/repos/yt-kevincarrera/kivo-player/releases/latest');

  /// The public page, which redirects to the newest tag and is not subject to
  /// the API's per-IP rate limit.
  static final Uri _defaultPage =
      Uri.parse('https://github.com/yt-kevincarrera/kivo-player/releases/latest');

  static const _timeout = Duration(seconds: 10);

  @override
  Future<UpdateInfo?> fetchLatest() async {
    Object apiError;
    try {
      return await _fromApi();
    } catch (e) {
      apiError = e;
    }
    // The API said no (rate limit, most likely) or failed outright. The page
    // still knows the newest tag, and the CI names every APK after it.
    try {
      final info = await _fromPage();
      // Worked, but the API's reason is worth keeping: a device that is
      // always rate-limited explains why release notes never show.
      debugPrint('UpdateChecker: API failed ($apiError), used the release page');
      return info;
    } catch (e) {
      // The UI only ever shows "no se pudo comprobar", so log the real reason
      // — both of them. A missing INTERNET permission once looked identical to
      // being offline; a silent non-200 looked identical to both.
      _log?.record(
          KivoFailure(KivoOp.updateCheck, 'API: $apiError; page: $e'));
      debugPrint('UpdateChecker.fetchLatest failed: API $apiError; page $e');
      return null;
    }
  }

  Future<UpdateInfo> _fromApi() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(_api);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'kivo-player');
      final resp = await req.close().timeout(_timeout);
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw _HttpStatus(_api, resp.statusCode, resp.headers);
      }
      final body = await resp.transform(utf8.decoder).join().timeout(_timeout);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      if (tag.isEmpty) throw const FormatException('release without tag_name');
      final assets = ((json['assets'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      final abi = await _primaryAbi();
      return UpdateInfo(
        version: _versionOf(tag),
        tagName: tag,
        apkUrl: pickApkAsset(assets, abi),
        releaseUrl: (json['html_url'] as String?) ?? '',
        notes: (json['body'] as String?) ?? '',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<UpdateInfo> _fromPage() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(_page);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, 'kivo-player');
      final resp = await req.close().timeout(_timeout);
      await resp.drain<void>();
      final location = resp.headers.value(HttpHeaders.locationHeader);
      if (!resp.isRedirect || location == null) {
        throw _HttpStatus(_page, resp.statusCode, resp.headers);
      }
      final target = _page.resolve(location);
      // …/releases/tag/v1.2.3
      final segments = target.pathSegments;
      final i = segments.lastIndexOf('tag');
      if (i < 0 || i + 1 >= segments.length) {
        throw FormatException('unexpected redirect to $target');
      }
      final tag = segments[i + 1];
      final abi = await _primaryAbi();
      return UpdateInfo(
        version: _versionOf(tag),
        tagName: tag,
        apkUrl: pickApkAsset(ciAssetsFor(_page, tag), abi),
        releaseUrl: target.toString(),
        // Only the API carries the body; the dialog copes with none.
        notes: '',
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _versionOf(String tag) =>
      tag.startsWith('v') || tag.startsWith('V') ? tag.substring(1) : tag;
}

/// The APKs the release workflow attaches to [tag], named exactly as
/// `.github/workflows/release.yml` renames them (`kivo-<tag>-<abi>.apk`), in
/// the shape [pickApkAsset] reads — for when only the tag is known.
List<Map<String, dynamic>> ciAssetsFor(Uri latestPage, String tag) {
  final base = latestPage.resolve('download/$tag/');
  return [
    for (final abi in const ['arm64-v8a', 'armeabi-v7a', 'x86_64'])
      {
        'name': 'kivo-$tag-$abi.apk',
        'browser_download_url': base.resolve('kivo-$tag-$abi.apk').toString(),
      },
  ];
}
