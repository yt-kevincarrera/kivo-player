import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/player/state/lock_state.dart';

void main() {
  test('lock/unlock toggles state', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(lockProvider), false);
    c.read(lockProvider.notifier).lock();
    expect(c.read(lockProvider), true);
    c.read(lockProvider.notifier).unlock();
    expect(c.read(lockProvider), false);
  });
}
