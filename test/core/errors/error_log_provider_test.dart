import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';

void main() {
  // Deliberately NOT a must-override provider: a session-only log is a valid
  // log, and making it mandatory meant any screen that forgot the override
  // crashed on the very code path that reports failures.
  test('un-overridden, it records to a working session-only log', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final log = container.read(errorLogProvider);
    log.record(const KivoFailure(KivoOp.openVideo, 'boom'));

    expect(log.entries().single.code, 'KV-501');
  });

  test('an overridden log records through the provider', () {
    final store = InMemoryErrorLogStore();
    final container = ProviderContainer(overrides: [
      errorLogProvider.overrideWithValue(
          ErrorLog(store, appVersion: '1.1.0', androidSdk: 28)),
    ]);
    addTearDown(container.dispose);

    container
        .read(errorLogProvider)
        .record(const KivoFailure(KivoOp.libraryScan, 'boom'));

    expect(container.read(errorLogProvider).entries().single.code, 'KV-201');
  });
}
