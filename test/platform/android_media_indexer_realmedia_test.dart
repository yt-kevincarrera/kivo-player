import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/platform/android/android_media_indexer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kivo/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ErrorLog log;
  late List<Map<String, Object>> rows;
  Uint8List? nativeThumbnail;
  Object? nativeError;

  setUp(() {
    log = ErrorLog(InMemoryErrorLogStore(), appVersion: 'test', androidSdk: 35);
    rows = [
      {
        'id': '7',
        'uri': 'content://media/external/file/7',
        'name': 'clip.RM',
        'sizeBytes': 1000,
        'dateModifiedMs': 1,
      },
    ];
    nativeThumbnail = null;
    nativeError = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'scan') return rows;
      if (nativeError != null) throw nativeError!;
      return nativeThumbnail;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'a library RealMedia thumbnail falls back to its playable URI',
    () async {
      final decoded = Uint8List.fromList([1, 2, 3]);
      String? source;
      final indexer = AndroidMediaIndexer(
        log,
        realMediaThumbnail: (uri) async {
          source = uri;
          return decoded;
        },
      );
      await indexer.scan();
      expect(await indexer.thumbnail('7'), decoded);
      expect(source, rows.single['uri']);
    },
  );

  test(
    'native exceptions still allow RealMedia fallback and are logged',
    () async {
      nativeError = PlatformException(code: 'THUMB_FAILED');
      rows.single['name'] = 'clip.RmVb';
      final indexer = AndroidMediaIndexer(
        log,
        realMediaThumbnail: (_) async => Uint8List.fromList([9]),
      );
      await indexer.scan();
      expect(await indexer.thumbnail('7'), [9]);
      expect(log.entries().single.code, 'KV-202');
    },
  );

  test('keeps native images and never probes ordinary videos', () async {
    var probes = 0;
    final indexer = AndroidMediaIndexer(
      log,
      realMediaThumbnail: (_) async {
        probes++;
        return null;
      },
    );
    nativeThumbnail = Uint8List.fromList([8]);
    await indexer.scan();
    expect(await indexer.thumbnail('7'), [8]);
    rows.single['name'] = 'clip.mp4';
    nativeThumbnail = null;
    await indexer.scan();
    expect(await indexer.thumbnail('7'), isNull);
    expect(probes, 0);
  });

  test(
    'coalesces requests, retains images on rescan, invalidates changed files',
    () async {
      var probes = 0;
      final ready = Completer<Uint8List?>();
      final indexer = AndroidMediaIndexer(
        log,
        realMediaThumbnail: (_) {
          probes++;
          return ready.future;
        },
      );
      await indexer.scan();
      final first = indexer.thumbnail('7');
      final second = indexer.thumbnail('7');
      ready.complete(Uint8List.fromList([3]));
      expect(await first, [3]);
      expect(await second, [3]);
      await indexer.scan();
      expect(await indexer.thumbnail('7'), [3]);
      expect(probes, 1);
      rows.single['dateModifiedMs'] = 2;
      await indexer.scan();
      await indexer.thumbnail('7');
      expect(probes, 2);
    },
  );

  test(
    'one failed decoder leaves other library thumbnails available',
    () async {
      rows.add({
        'id': '8',
        'uri': 'content://media/external/file/8',
        'name': 'good.rm',
      });
      final indexer = AndroidMediaIndexer(
        log,
        realMediaThumbnail: (uri) async {
          if (uri.endsWith('/7')) throw StateError('invalid media');
          return Uint8List.fromList([4]);
        },
      );
      await indexer.scan();
      expect(await indexer.thumbnail('7'), isNull);
      expect(await indexer.thumbnail('8'), [4]);
      expect(log.entries().single.code, 'KV-202');
    },
  );

  test('thumbnail cache is bounded while browsing a large library', () async {
    rows = List.generate(
      49,
      (i) => {
        'id': '$i',
        'uri': 'content://media/external/file/$i',
        'name': '$i.rm',
      },
    );
    var probes = 0;
    final indexer = AndroidMediaIndexer(
      log,
      realMediaThumbnail: (_) async {
        probes++;
        return Uint8List.fromList([1]);
      },
    );
    await indexer.scan();
    for (var i = 0; i < 49; i++) {
      await indexer.thumbnail('$i');
    }
    await indexer.thumbnail('48');
    expect(probes, 49);
    await indexer.thumbnail('0');
    expect(probes, 50);
  });

  test(
    'a temporary failure can recover on the next thumbnail request',
    () async {
      var available = false;
      final indexer = AndroidMediaIndexer(
        log,
        realMediaThumbnail: (_) async {
          return available ? Uint8List.fromList([7]) : null;
        },
      );
      await indexer.scan();
      expect(await indexer.thumbnail('7'), isNull);
      available = true;
      expect(await indexer.thumbnail('7'), [7]);
    },
  );
}
