import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import '../../fakes/fakes.dart';

void main() {
  test('errorLogProvider must be overridden', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(() => container.read(errorLogProvider), throwsUnimplementedError);
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
