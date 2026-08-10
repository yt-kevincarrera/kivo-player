import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import '../../fakes/fakes.dart';

ErrorLog _log(ErrorLogStore store, {DateTime Function()? now}) =>
    ErrorLog(store, appVersion: '1.1.0', androidSdk: 28, now: now);

void main() {
  test('record stores code, op, detail and device context', () {
    final store = InMemoryErrorLogStore();
    final log = _log(store, now: () => DateTime.fromMillisecondsSinceEpoch(1000));

    log.record(const KivoFailure(KivoOp.libraryScan, 'no such column relative_path'));

    final entries = log.entries();
    expect(entries, hasLength(1));
    expect(entries.first.code, 'KV-201');
    expect(entries.first.op, 'libraryScan');
    expect(entries.first.detail, contains('relative_path'));
    expect(entries.first.appVersion, '1.1.0');
    expect(entries.first.androidSdk, 28);
    expect(entries.first.timestampMs, 1000);
  });

  test('record returns the failure so call sites can throw it', () {
    const failure = KivoFailure(KivoOp.delete, 'nope');
    expect(_log(InMemoryErrorLogStore()).record(failure), same(failure));
  });

  test('entries come back newest first', () {
    final log = _log(InMemoryErrorLogStore());
    log.record(const KivoFailure(KivoOp.libraryScan, 'first'));
    log.record(const KivoFailure(KivoOp.delete, 'second'));

    expect(log.entries().map((e) => e.detail).toList(), ['second', 'first']);
  });

  test('keeps only the last maxEntries failures', () {
    final log = _log(InMemoryErrorLogStore());
    for (var i = 0; i < ErrorLog.maxEntries + 5; i++) {
      log.record(KivoFailure(KivoOp.libraryScan, 'failure $i'));
    }

    final entries = log.entries();
    expect(entries, hasLength(ErrorLog.maxEntries));
    expect(entries.first.detail, 'failure ${ErrorLog.maxEntries + 4}');
    expect(entries.last.detail, 'failure 5');
  });

  test('survives a round trip through the store', () {
    final store = InMemoryErrorLogStore();
    _log(store).record(const KivoFailure(KivoOp.vaultHide, 'boom'));

    expect(_log(store).entries().single.code, 'KV-401');
  });

  test('clear empties the log', () async {
    final log = _log(InMemoryErrorLogStore());
    log.record(const KivoFailure(KivoOp.share, 'boom'));

    await log.clear();

    expect(log.entries(), isEmpty);
  });

  test('a store that throws never propagates', () {
    final log = _log(ThrowingErrorLogStore());

    expect(() => log.record(const KivoFailure(KivoOp.rename, 'boom')), returnsNormally);
    expect(() => log.entries(), returnsNormally);
    expect(log.entries(), isEmpty);
    expect(log.clear, returnsNormally);
  });
}
