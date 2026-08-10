import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/platform/android/android_media_file_ops.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kivo/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late ErrorLog log;

  setUp(() => log =
      ErrorLog(InMemoryErrorLogStore(), appVersion: '1.1.0', androidSdk: 28));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void mockThrow() {
    messenger.setMockMethodCallHandler(channel,
        (call) async => throw PlatformException(code: 'X', message: 'denied'));
  }

  void mockReply(Object? value) {
    messenger.setMockMethodCallHandler(channel, (call) async => value);
  }

  test('a thrown delete still returns error, and is logged as KV-301', () async {
    mockThrow();

    expect(await AndroidMediaFileOps(log).delete('uri'), FileOpStatus.error);
    expect(log.entries().single.code, 'KV-301');
  });

  test('an error status from the platform is logged too', () async {
    mockReply('error');

    expect(await AndroidMediaFileOps(log).delete('uri'), FileOpStatus.error);
    expect(log.entries().single.code, 'KV-301');
  });

  test('a cancelled delete is not an error and is not logged', () async {
    mockReply('cancelled');

    expect(await AndroidMediaFileOps(log).delete('uri'), FileOpStatus.cancelled);
    expect(log.entries(), isEmpty);
  });

  test('a thrown rename is logged as KV-302', () async {
    mockThrow();

    final out = await AndroidMediaFileOps(log).rename('uri', 'nuevo');
    expect(out.status, FileOpStatus.error);
    expect(log.entries().single.code, 'KV-302');
  });

  test('a thrown share is logged as KV-303', () async {
    mockThrow();

    await AndroidMediaFileOps(log).share('uri');
    expect(log.entries().single.code, 'KV-303');
  });
}
