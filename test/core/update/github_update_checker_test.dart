import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/update/update_checker.dart';

/// A local stand-in for GitHub: the API and the public releases page.
class _FakeGithub {
  late HttpServer server;
  int apiStatus = 200;
  String latestTag = 'v9.9.9';
  bool pageRedirects = true;
  int apiHits = 0;
  int pageHits = 0;

  Uri get api => Uri.parse('http://127.0.0.1:${server.port}/api/latest');
  Uri get page =>
      Uri.parse('http://127.0.0.1:${server.port}/o/r/releases/latest');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      if (req.uri.path == '/api/latest') {
        apiHits++;
        res.statusCode = apiStatus;
        if (apiStatus == 403) {
          res.headers.set('x-ratelimit-remaining', '0');
          res.headers.set('x-ratelimit-reset', '1700000000');
          res.write('{"message":"API rate limit exceeded"}');
        } else {
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({
            'tag_name': latestTag,
            'html_url': 'https://example/release',
            'body': '## Novedades',
            'assets': [
              {
                'name': 'kivo-$latestTag-arm64-v8a.apk',
                'browser_download_url': 'https://example/arm64.apk',
              },
            ],
          }));
        }
      } else if (req.uri.path == '/o/r/releases/latest') {
        pageHits++;
        if (pageRedirects) {
          res.statusCode = HttpStatus.found;
          res.headers.set(HttpHeaders.locationHeader,
              'http://127.0.0.1:${server.port}/o/r/releases/tag/$latestTag');
        } else {
          res.statusCode = HttpStatus.serviceUnavailable;
        }
      } else {
        res.statusCode = HttpStatus.notFound;
      }
      await res.close();
    });
  }
}

void main() {
  late _FakeGithub gh;
  late ErrorLog log;

  setUp(() async {
    gh = _FakeGithub();
    await gh.start();
    log = ErrorLog(InMemoryErrorLogStore(), appVersion: 't', androidSdk: 0);
  });
  tearDown(() => gh.server.close(force: true));

  GithubUpdateChecker checker() => GithubUpdateChecker(
        () async => 'arm64-v8a',
        log: log,
        apiEndpoint: gh.api,
        latestPage: gh.page,
      );

  test('the API answer is used when it works, notes included', () async {
    final info = await checker().fetchLatest();
    expect(info!.version, '9.9.9');
    expect(info.notes, '## Novedades');
    expect(info.apkUrl, 'https://example/arm64.apk');
    expect(gh.pageHits, 0);
    expect(log.entries(), isEmpty);
  });

  // The reported KV-601: the API's per-IP limit (60/h) is shared by every
  // phone behind the same carrier IP. The public page has no such limit.
  test('a rate-limited API falls back to the release page', () async {
    gh.apiStatus = 403;
    final info = await checker().fetchLatest();
    expect(info, isNotNull);
    expect(info!.tagName, 'v9.9.9');
    expect(info.version, '9.9.9');
    expect(info.apkUrl, endsWith('/o/r/releases/download/v9.9.9/kivo-v9.9.9-arm64-v8a.apk'));
    expect(info.notes, '');
    expect(log.entries(), isEmpty, reason: 'recovered: nothing to report');
  });

  test('the fallback picks the APK for this device\'s ABI', () async {
    gh.apiStatus = 403;
    final info = await GithubUpdateChecker(() async => 'armeabi-v7a',
            apiEndpoint: gh.api, latestPage: gh.page)
        .fetchLatest();
    expect(info!.apkUrl, endsWith('kivo-v9.9.9-armeabi-v7a.apk'));
  });

  test('when both fail, KV-601 is logged with the real reasons', () async {
    gh.apiStatus = 403;
    gh.pageRedirects = false;
    expect(await checker().fetchLatest(), isNull);
    final entry = log.entries().single;
    expect(entry.code, 'KV-601');
    expect(entry.detail, contains('HTTP 403'));
    expect(entry.detail, contains('rate limit remaining 0'));
    expect(entry.detail, contains('HTTP 503'));
  });

  test('ciAssetsFor names the APKs exactly as the release workflow does', () {
    final assets = ciAssetsFor(
        Uri.parse('https://github.com/o/r/releases/latest'), 'v1.2.3');
    expect(assets.map((a) => a['browser_download_url']), [
      'https://github.com/o/r/releases/download/v1.2.3/kivo-v1.2.3-arm64-v8a.apk',
      'https://github.com/o/r/releases/download/v1.2.3/kivo-v1.2.3-armeabi-v7a.apk',
      'https://github.com/o/r/releases/download/v1.2.3/kivo-v1.2.3-x86_64.apk',
    ]);
  });
}
