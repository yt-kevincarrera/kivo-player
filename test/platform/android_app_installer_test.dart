import 'dart:async';

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
    'preview forwards optional metadata and never queues a download',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'bytes': 690795, 'fullBytes': 35076444, 'partial': true};
      });
      final installer = AndroidAppInstaller();

      final preview = await installer.previewUpdate(
        'https://example.com/full.apk',
        manifestUrl: 'https://example.com/kivo-update-v1.json',
      );
      expect(preview, isNotNull);
      expect(preview!.bytes, 690795);
      expect(preview.fullBytes, 35076444);
      expect(preview.partial, isTrue);
      await installer.previewUpdate('https://example.com/legacy.apk');

      expect(calls.map((call) => call.method), [
        'previewUpdate',
        'previewUpdate',
      ]);
      expect(calls.first.arguments, {
        'url': 'https://example.com/full.apk',
        'manifestUrl': 'https://example.com/kivo-update-v1.json',
      });
      expect(calls.last.arguments, {'url': 'https://example.com/legacy.apk'});
    },
  );

  test('preview keeps integral codec numbers exact', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'previewUpdate');
      return {'bytes': 690795.0, 'fullBytes': 35076444.0, 'partial': false};
    });

    final preview = await AndroidAppInstaller().previewUpdate(
      'https://example.com/full.apk',
    );
    expect(preview!.bytes, 690795);
    expect(preview.fullBytes, 35076444);
    expect(preview.partial, isFalse);
  });

  test('preview preserves unknown sizes without inventing bytes', () async {
    for (final payload in [
      <String, Object?>{},
      {'bytes': null, 'fullBytes': null, 'partial': false},
      {'bytes': null, 'fullBytes': 35076444},
    ]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'previewUpdate');
        return payload;
      });

      final preview = await AndroidAppInstaller().previewUpdate(
        'https://example.com/full.apk',
      );
      expect(preview, isNotNull);
      expect(preview!.bytes, isNull);
      expect(preview.fullBytes, payload['fullBytes']);
      expect(preview.partial, isFalse);
    }
  });

  test('preview ignores each invalid byte count independently', () async {
    final invalidSizes = <Object>[
      0,
      0.0,
      -1,
      -1.0,
      '690795',
      true,
      690795.5,
      double.nan,
      double.infinity,
      double.negativeInfinity,
      <int>[],
      <String, int>{'value': 1},
    ];
    for (final invalid in invalidSizes) {
      for (final invalidField in ['bytes', 'fullBytes']) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'previewUpdate');
          return {
            'bytes': invalidField == 'bytes' ? invalid : 690795,
            'fullBytes': invalidField == 'fullBytes' ? invalid : 35076444,
            'partial': true,
          };
        });

        final preview = await AndroidAppInstaller().previewUpdate(
          'https://example.com/full.apk',
        );
        expect(preview, isNotNull, reason: '$invalidField: $invalid');
        expect(
          preview!.bytes,
          invalidField == 'bytes' ? isNull : 690795,
          reason: '$invalidField: $invalid',
        );
        expect(
          preview.fullBytes,
          invalidField == 'fullBytes' ? isNull : 35076444,
          reason: '$invalidField: $invalid',
        );
        expect(preview.partial, isTrue);
      }
    }
  });

  test(
    'preview returns null for absent or malformed native payloads',
    () async {
      for (final payload in <Object?>[
        null,
        'not metadata',
        123,
        false,
        <int>[],
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'previewUpdate');
          return payload;
        });

        expect(
          await AndroidAppInstaller().previewUpdate(
            'https://example.com/full.apk',
          ),
          isNull,
        );
      }
    },
  );

  test('preview returns null when the native plugin is unavailable', () async {
    final calls = <MethodCall>[];
    for (final error in [
      PlatformException(code: 'UNAVAILABLE'),
      MissingPluginException('preview not supported by this build'),
    ]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        throw error;
      });
      expect(
        await AndroidAppInstaller().previewUpdate(
          'https://example.com/full.apk',
        ),
        isNull,
      );
    }
    expect(calls.map((call) => call.method), [
      'previewUpdate',
      'previewUpdate',
    ]);
  });

  testWidgets('preview times out after 15 seconds without queueing a download', (
    tester,
  ) async {
    final nativeResponse = Completer<Object?>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return nativeResponse.future;
    });
    var completions = 0;
    final preview = AndroidAppInstaller()
        .previewUpdate('https://example.com/full.apk')
        .then((value) {
          completions++;
          return value;
        });

    try {
      await tester.pump();
      expect(calls.map((call) => call.method), ['previewUpdate']);
      expect(completions, 0);

      await tester.pump(const Duration(seconds: 14));
      expect(completions, 0);

      await tester.pump(const Duration(seconds: 1));
      expect(completions, 1);
      expect(await preview, isNull);

      // Native work may finish after Dart has stopped waiting for its preview.
      nativeResponse.complete({
        'bytes': 690795,
        'fullBytes': 35076444,
        'partial': true,
      });
      await tester.pump();
      expect(completions, 1);
      expect(calls.map((call) => call.method), ['previewUpdate']);
      expect(tester.takeException(), isNull);
    } finally {
      if (!nativeResponse.isCompleted) nativeResponse.complete(null);
      await tester.pump();
    }
  });

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

  test(
    'pending reports observed heat separately and clears it as status changes',
    () async {
      for (final status in ['pending', 'running', 'paused', 'done']) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => {'status': status, 'deviceHot': true},
        );
        final progress = await AndroidAppInstaller().downloadStatus(81);
        expect(progress.deviceHot, status == 'pending');
      }
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'status': 'pending'},
      );
      expect(
        (await AndroidAppInstaller().downloadStatus(81)).deviceHot,
        isFalse,
      );
    },
  );

  test(
    'pause reasons preserve Wi-Fi and unknown instead of inventing a network failure',
    () async {
      for (final entry in {
        'network': DownloadStage.pausedNetwork,
        'retry': DownloadStage.pausedRetry,
        'wifi': DownloadStage.pausedWifi,
        'unknown': DownloadStage.pausedUnknown,
        'new-system-reason': DownloadStage.pausedUnknown,
        null: DownloadStage.pausedUnknown,
      }.entries) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'paused', 'reason': entry.key},
        );
        final progress = await AndroidAppInstaller().downloadStatus(81);
        expect(progress.stage, entry.value);
        expect(progress.isPaused, isTrue);
        expect(progress.isSettled, isFalse);
      }
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
