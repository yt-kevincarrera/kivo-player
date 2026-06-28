import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import '../../fakes/fakes.dart';

void main() {
  test('positionProvider reflects engine stream', () async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final container = ProviderContainer(overrides: [
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);

    final sub = container.listen(positionProvider, (_, __) {});
    engine.emitPosition(const Duration(seconds: 7));
    await Future<void>.delayed(Duration.zero);

    expect(sub.read().value, const Duration(seconds: 7));
  });
}
