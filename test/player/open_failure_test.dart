import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/player/open/guarded_open.dart';
import '../fakes/fakes.dart';

void main() {
  test('a failing open is logged as KV-501 and rethrown as a KivoFailure',
      () async {
    final store = InMemoryErrorLogStore();
    final log = ErrorLog(store, appVersion: '1.1.0', androidSdk: 28);
    final engine = FakePlaybackEngine()..openError = StateError('codec missing');

    await expectLater(
      guardedOpen(engine, '/videos/x.mkv', log),
      throwsA(isA<KivoFailure>().having((f) => f.code, 'code', 'KV-501')),
    );
    expect(log.entries().single.detail, contains('codec missing'));
  });

  test('a successful open logs nothing', () async {
    final log =
        ErrorLog(InMemoryErrorLogStore(), appVersion: '1.1.0', androidSdk: 28);

    await guardedOpen(FakePlaybackEngine(), '/videos/x.mkv', log);

    expect(log.entries(), isEmpty);
  });
}
