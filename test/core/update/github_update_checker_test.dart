import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/update/update_checker.dart';
import 'package:kivo_player/core/update/update_info.dart';

Future<UpdateInfo?> _fetchWithAssets(
  List<Map<String, Object?>> assets, {
  String abi = 'arm64-v8a',
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/api/latest') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'tag_name': 'v9.9.9', 'assets': assets}),
      );
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  try {
    final base = 'http://127.0.0.1:${server.port}';
    return await GithubUpdateChecker(
      () async => abi,
      apiEndpoint: Uri.parse('$base/api/latest'),
      latestPage: Uri.parse('$base/releases/latest'),
    ).fetchLatest();
  } finally {
    await server.close(force: true);
  }
}

/// A local stand-in for GitHub: the API and the public releases page.
class _FakeGithub {
  late HttpServer server;
  int apiStatus = 200;
  String latestTag = 'v9.9.9';
  bool pageRedirects = true;
  int apiHits = 0;
  int pageHits = 0;
  bool hasManifest = false;

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
          res.write(
            jsonEncode({
              'tag_name': latestTag,
              'html_url': 'https://example/release',
              'body': '## Novedades',
              'assets': [
                if (hasManifest)
                  {
                    'name': 'kivo-update-v1.json',
                    'browser_download_url':
                        'https://example/kivo-update-v1.json',
                  },
                {
                  'name': 'kivo-$latestTag-arm64-v8a.apk',
                  'browser_download_url': 'https://example/arm64.apk',
                },
              ],
            }),
          );
        }
      } else if (req.uri.path == '/o/r/releases/latest') {
        pageHits++;
        if (pageRedirects) {
          res.statusCode = HttpStatus.found;
          res.headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${server.port}/o/r/releases/tag/$latestTag',
          );
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
    expect(info.manifestUrl, isNull);
    expect(info.apkSizeBytes, isNull);
    expect(gh.pageHits, 0);
    expect(log.entries(), isEmpty);
  });

  test(
    'the optional release manifest is passed to the native updater',
    () async {
      gh.hasManifest = true;
      final info = await checker().fetchLatest();
      expect(info!.manifestUrl, 'https://example/kivo-update-v1.json');
    },
  );

  test('API size follows the same APK selected for each device ABI', () async {
    final assets = <Map<String, Object?>>[
      {
        'name': 'kivo-v9.9.9-armeabi-v7a.apk',
        'browser_download_url': 'https://example/v7.apk',
        'size': 32241466,
      },
      {
        'name': 'kivo-update-v1.json',
        'browser_download_url': 'https://example/kivo-update-v1.json',
        'size': 2786,
      },
      {
        'name': 'kivo-v9.9.9-arm64-v8a-from-v9.9.8.kdelta',
        'browser_download_url': 'https://example/patch.kdelta',
        'size': 690795,
      },
      {
        'name': 'kivo-v9.9.9-arm64-v8a.apk',
        'browser_download_url': 'https://example/arm64.apk',
        'size': 35076444,
      },
      {
        'name': 'kivo-v9.9.9-x86_64.apk',
        'browser_download_url': 'https://example/x86.apk',
        'size': 39997641,
      },
    ];
    for (final (abi, file, bytes) in [
      ('arm64-v8a', 'arm64.apk', 35076444),
      ('armeabi-v7a', 'v7.apk', 32241466),
      ('x86_64', 'x86.apk', 39997641),
    ]) {
      final info = await _fetchWithAssets(assets, abi: abi);
      expect(info!.apkUrl, 'https://example/$file');
      expect(info.apkSizeBytes, bytes);
    }
  });

  test(
    'API size follows the chosen fallback APK when an ABI is absent',
    () async {
      final assets = <Map<String, Object?>>[
        {
          'name': 'kivo-v9.9.9-armeabi-v7a.apk',
          'browser_download_url': 'https://example/v7.apk',
          'size': 32241466,
        },
        {
          'name': 'kivo-v9.9.9-arm64-v8a.apk',
          'browser_download_url': 'https://example/arm64.apk',
          'size': 35076444,
        },
      ];
      final preferredFallback = await _fetchWithAssets(assets, abi: 'unknown');
      expect(preferredFallback!.apkUrl, 'https://example/arm64.apk');
      expect(preferredFallback.apkSizeBytes, 35076444);

      final firstApkFallback = await _fetchWithAssets([
        assets.first,
      ], abi: 'x86_64');
      expect(firstApkFallback!.apkUrl, 'https://example/v7.apk');
      expect(firstApkFallback.apkSizeBytes, 32241466);
    },
  );

  test('missing or invalid selected APK sizes remain unknown', () async {
    for (final sizeMetadata in <Map<String, Object?>>[
      {},
      {'size': null},
      {'size': 0},
      {'size': -1},
      {'size': '35076444'},
      {'size': 1.5},
      {'size': true},
    ]) {
      final info = await _fetchWithAssets([
        {
          'name': 'kivo-v9.9.9-armeabi-v7a.apk',
          'browser_download_url': 'https://example/v7.apk',
          'size': 32241466,
        },
        {
          'name': 'kivo-v9.9.9-arm64-v8a.apk',
          'browser_download_url': 'https://example/arm64.apk',
          ...sizeMetadata,
        },
      ]);
      expect(info, isNotNull, reason: '$sizeMetadata');
      expect(info!.apkUrl, 'https://example/arm64.apk');
      expect(info.apkSizeBytes, isNull, reason: '$sizeMetadata');
    }
  });

  test('release assets without an APK cannot supply an APK size', () async {
    final info = await _fetchWithAssets([
      {
        'name': 'kivo-update-v1.json',
        'browser_download_url': 'https://example/kivo-update-v1.json',
        'size': 2786,
      },
    ]);
    expect(info!.apkUrl, isNull);
    expect(info.apkSizeBytes, isNull);
  });

  // The reported KV-601: the API's per-IP limit (60/h) is shared by every
  // phone behind the same carrier IP. The public page has no such limit.
  test('a rate-limited API falls back to the release page', () async {
    gh.apiStatus = 403;
    final info = await checker().fetchLatest();
    expect(info, isNotNull);
    expect(info!.tagName, 'v9.9.9');
    expect(info.version, '9.9.9');
    expect(
      info.apkUrl,
      endsWith('/o/r/releases/download/v9.9.9/kivo-v9.9.9-arm64-v8a.apk'),
    );
    expect(info.notes, '');
    expect(
      info.manifestUrl,
      endsWith('/o/r/releases/download/v9.9.9/kivo-update-v1.json'),
    );
    expect(info.apkSizeBytes, isNull);
    expect(log.entries(), isEmpty, reason: 'recovered: nothing to report');
  });

  test('the fallback picks the APK for this device\'s ABI', () async {
    gh.apiStatus = 403;
    final info = await GithubUpdateChecker(
      () async => 'armeabi-v7a',
      apiEndpoint: gh.api,
      latestPage: gh.page,
    ).fetchLatest();
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
      Uri.parse('https://github.com/o/r/releases/latest'),
      'v1.2.3',
    );
    expect(assets.map((a) => a['browser_download_url']), [
      'https://github.com/o/r/releases/download/v1.2.3/kivo-v1.2.3-arm64-v8a.apk',
      'https://github.com/o/r/releases/download/v1.2.3/kivo-v1.2.3-armeabi-v7a.apk',
      'https://github.com/o/r/releases/download/v1.2.3/kivo-v1.2.3-x86_64.apk',
    ]);
  });
}
