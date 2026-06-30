import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/player/gestures/ripple_state.dart';

void main() {
  test('same-side double-taps accumulate within the window; id increments', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final r = c.read(rippleControllerProvider);

      r.bump(left: false, seconds: 10);
      var e = c.read(rippleProvider)!;
      expect(e.left, false);
      expect(e.seconds, 10);
      final firstId = e.id;

      r.bump(left: false, seconds: 10); // same side, within window
      e = c.read(rippleProvider)!;
      expect(e.seconds, 20);
      expect(e.id, greaterThan(firstId));
    });
  });

  test('opposite side resets the total', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final r = c.read(rippleControllerProvider);
      r.bump(left: false, seconds: 10);
      r.bump(left: true, seconds: 10); // switch side
      final e = c.read(rippleProvider)!;
      expect(e.left, true);
      expect(e.seconds, 10);
    });
  });

  test('window expiry resets the total', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final r = c.read(rippleControllerProvider);
      r.bump(left: false, seconds: 10);
      async.elapse(const Duration(milliseconds: 1200));
      r.bump(left: false, seconds: 10);
      expect(c.read(rippleProvider)!.seconds, 10);
    });
  });
}
