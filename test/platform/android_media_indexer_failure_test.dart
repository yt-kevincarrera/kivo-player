import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/platform/android/android_media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kivo/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late ErrorLog log;

  setUp(() => log =
      ErrorLog(InMemoryErrorLogStore(), appVersion: '1.1.0', androidSdk: 28));

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void mockFailure(String code, String message) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: code, message: message);
    });
  }

  test('scan throws KV-201 instead of the PlatformException', () async {
    mockFailure('SCAN_FAILED', 'no such column relative_path');

    await expectLater(
      AndroidMediaIndexer(log).scan(),
      throwsA(isA<KivoFailure>()
          .having((f) => f.code, 'code', 'KV-201')
          .having((f) => f.message, 'message', 'No pudimos leer tu biblioteca')),
    );
  });

  test('a failed scan lands in the log with its technical detail', () async {
    mockFailure('SCAN_FAILED', 'no such column relative_path');

    await AndroidMediaIndexer(log).scan().catchError((_) => <VideoItem>[]);

    final entry = log.entries().single;
    expect(entry.code, 'KV-201');
    expect(entry.op, 'libraryScan');
    expect(entry.detail, contains('relative_path'));
  });

  test('a failed thumbnail is logged as KV-202 but returns null', () async {
    mockFailure('THUMB_FAILED', 'decoder gave up');

    expect(await AndroidMediaIndexer(log).thumbnail('7'), isNull);
    expect(log.entries().single.code, 'KV-202');
  });
}
