import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/android/android_app_installer.dart';
import 'package:kivo_player/platform/interfaces/app_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kivo/update');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'enqueue forwards an optional manifest without changing the APK fallback',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 81;
      });
      final installer = AndroidAppInstaller();

      expect(
        await installer.enqueueUpdate(
          'https://example.com/full.apk',
          'kivo.apk',
          manifestUrl: 'https://example.com/kivo-update-v1.json',
        ),
        81,
      );
      expect(
        await installer.enqueueUpdate(
          'https://example.com/full.apk',
          'old.apk',
        ),
        81,
      );

      expect(calls.map((call) => call.method), [
        'enqueueUpdate',
        'enqueueUpdate',
      ]);
      expect(calls.first.arguments, {
        'url': 'https://example.com/full.apk',
        'fileName': 'kivo.apk',
        'manifestUrl': 'https://example.com/kivo-update-v1.json',
      });
      expect(calls.last.arguments, {
        'url': 'https://example.com/full.apk',
        'fileName': 'old.apk',
      });
    },
  );

  test(
    'preparing maps to an unsettled stage with partial transfer metadata',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'downloadStatus');
        expect(call.arguments, {'id': 81});
        return {
          'status': 'preparing',
          'received': 100.0,
          'total': 100,
          'partial': true,
          'fallback': false,
        };
      });

      final progress = await AndroidAppInstaller().downloadStatus(81);
      expect(progress.stage, DownloadStage.preparing);
      expect(progress.received, 100);
      expect(progress.total, 100);
      expect(progress.partial, isTrue);
      expect(progress.fallback, isFalse);
      expect(progress.isSettled, isFalse);
      expect(progress.fraction, isNull);
    },
  );

  test('full fallback keeps the same native handle and its progress', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'installDownload'
          ? 'started'
          : {
              'status': 'running',
              'received': 25,
              'total': 100,
              'fallback': true,
            };
    });
    final installer = AndroidAppInstaller();

    final progress = await installer.downloadStatus(81);
    expect(progress.stage, DownloadStage.running);
    expect(progress.fallback, isTrue);
    expect(progress.partial, isFalse);
    expect(progress.fraction, 0.25);
    expect(await installer.installDownload(81), InstallOutcome.started);
    expect(calls.map((call) => call.arguments), [
      {'id': 81},
      {'id': 81},
    ]);
  });

  test(
    'legacy completed progress defaults new transfer flags to false',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'status': 'done', 'received': 100, 'total': 100},
      );

      final progress = await AndroidAppInstaller().downloadStatus(81);
      expect(progress.stage, DownloadStage.done);
      expect(progress.isSettled, isTrue);
      expect(progress.partial, isFalse);
      expect(progress.fallback, isFalse);
    },
  );

  test(
    'pendingUpdate recovers the durable native job and target version',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'pendingUpdate');
        return {'id': 81.0, 'version': '1.1.0'};
      });

      final pending = await AndroidAppInstaller().pendingUpdate();
      expect(pending?.id, 81);
      expect(pending?.version, '1.1.0');
    },
  );

  test('missing or malformed pending work is not adopted', () async {
    for (final payload in [
      null,
      {'id': -1, 'version': '1.1.0'},
      {'id': 81},
      {'id': 81, 'version': ''},
      {'id': '81', 'version': '1.1.0'},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => payload);
      expect(await AndroidAppInstaller().pendingUpdate(), isNull);
    }
  });

  test('unsupported pending recovery and status fail closed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'UNAVAILABLE');
    });
    final installer = AndroidAppInstaller();
    expect(await installer.pendingUpdate(), isNull);
    expect(await installer.downloadStatus(81), DownloadProgress.gone);
  });
}
