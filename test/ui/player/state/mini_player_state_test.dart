import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';

void main() {
  test('playerMinimizedProvider defaults to false', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(playerMinimizedProvider), false);
  });

  test('miniPlayerThumbnailProvider defaults to null', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(miniPlayerThumbnailProvider), isNull);
  });
}
