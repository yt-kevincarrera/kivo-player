import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/library/played.dart';

void main() {
  test('InMemoryPlayedStore: isPlayed false initially, true after markPlayed',
      () async {
    final store = InMemoryPlayedStore();
    expect(store.isPlayed('a'), isFalse);
    await store.markPlayed('a');
    expect(store.isPlayed('a'), isTrue);
    expect(store.keys(), contains('a'));
  });

  test('playedKeysProvider reflects marked keys after invalidation',
      () async {
    final store = InMemoryPlayedStore();
    final container = ProviderContainer(overrides: [
      playedStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);

    expect(container.read(playedKeysProvider), isEmpty);

    await store.markPlayed('a');
    container.invalidate(playedKeysProvider);

    expect(container.read(playedKeysProvider), {'a'});
  });
}
