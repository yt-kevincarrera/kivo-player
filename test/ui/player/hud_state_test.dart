import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/player/state/hud_state.dart';

void main() {
  test('show sets state and clears after 800ms', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      c.read(hudProvider.notifier).show(HudKind.volume, 0.8, '80%');
      expect(c.read(hudProvider)!.kind, HudKind.volume);
      expect(c.read(hudProvider)!.label, '80%');
      async.elapse(const Duration(milliseconds: 800));
      expect(c.read(hudProvider), isNull);
      c.dispose();
    });
  });
}
