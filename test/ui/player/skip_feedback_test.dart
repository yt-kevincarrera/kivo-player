import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/player/state/hud_state.dart';
import 'package:kivo_player/ui/player/state/skip_feedback.dart';

void main() {
  test('consecutive same-direction skips accumulate within the window', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final f = c.read(skipFeedbackProvider);

      f.bump(10);
      expect(c.read(hudProvider)!.label, '+10s');
      async.elapse(const Duration(milliseconds: 300));
      f.bump(10);
      expect(c.read(hudProvider)!.label, '+20s');

      async.elapse(const Duration(milliseconds: 1200)); // window expires
      f.bump(10);
      expect(c.read(hudProvider)!.label, '+10s'); // reset
    });
  });

  test('direction change resets the running total', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final f = c.read(skipFeedbackProvider);
      f.bump(10);
      f.bump(-10); // opposite dir within window
      expect(c.read(hudProvider)!.label, '-10s');
    });
  });
}
