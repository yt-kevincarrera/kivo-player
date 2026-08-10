import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/platform/android/android_vault_ops.dart';
import '../fakes/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kivo/vault');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late ErrorLog log;

  setUp(() => log =
      ErrorLog(InMemoryErrorLogStore(), appVersion: '1.1.0', androidSdk: 28));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void mockReply(Object? Function(MethodCall call) reply) {
    messenger.setMockMethodCallHandler(channel, (call) async => reply(call));
  }

  test('a totally failed hide throws KV-401', () async {
    mockReply((_) => <dynamic>[]);

    await expectLater(
      AndroidVaultOps(log).hide(['uri-1', 'uri-2']),
      throwsA(isA<KivoFailure>().having((f) => f.code, 'code', 'KV-401')),
    );
    expect(log.entries().single.op, 'vaultHide');
  });

  test('a partial hide returns what worked and logs the gap', () async {
    mockReply((_) => <dynamic>[
          {'id': '1', 'privatePath': '/vault/1.mp4'}
        ]);

    final result = await AndroidVaultOps(log).hide(['uri-1', 'uri-2', 'uri-3']);

    expect(result, hasLength(1));
    final entry = log.entries().single;
    expect(entry.code, 'KV-401');
    expect(entry.detail, contains('1'));
    expect(entry.detail, contains('3'));
  });

  test('a fully successful hide logs nothing', () async {
    mockReply((_) => <dynamic>[
          {'id': '1'},
          {'id': '2'}
        ]);

    expect(await AndroidVaultOps(log).hide(['uri-1', 'uri-2']), hasLength(2));
    expect(log.entries(), isEmpty);
  });

  test('an empty request logs nothing and throws nothing', () async {
    mockReply((_) => <dynamic>[]);

    expect(await AndroidVaultOps(log).hide([]), isEmpty);
    expect(log.entries(), isEmpty);
  });

  test('a channel error on unhide throws KV-402', () async {
    messenger.setMockMethodCallHandler(channel,
        (call) async => throw PlatformException(code: 'X', message: 'move failed'));

    await expectLater(
      AndroidVaultOps(log).unhide([
        {'privatePath': '/vault/1.mp4'}
      ]),
      throwsA(isA<KivoFailure>().having((f) => f.code, 'code', 'KV-402')),
    );
  });

  test('a channel error on deleteForever throws KV-403', () async {
    messenger.setMockMethodCallHandler(channel,
        (call) async => throw PlatformException(code: 'X', message: 'unlink failed'));

    await expectLater(
      AndroidVaultOps(log).deleteForever(['/vault/1.mp4']),
      throwsA(isA<KivoFailure>().having((f) => f.code, 'code', 'KV-403')),
    );
  });
}
