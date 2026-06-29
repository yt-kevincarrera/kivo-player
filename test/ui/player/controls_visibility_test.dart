import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import '../../fakes/fakes.dart';

void main() {
  test('toggle shows then auto-hides after controlsAutoHideMs', () async {
    // Load settings outside fakeAsync so the async Future resolves normally.
    final s = await SettingsService.load(InMemorySettingsStore());

    fakeAsync((async) {
      final c = ProviderContainer(
        overrides: [settingsServiceProvider.overrideWithValue(s)],
      );
      addTearDown(c.dispose);

      expect(c.read(controlsVisibleProvider), false);

      c.read(controlsVisibleProvider.notifier).toggle();
      expect(c.read(controlsVisibleProvider), true);

      async.elapse(const Duration(milliseconds: 3000));
      expect(c.read(controlsVisibleProvider), false);
    });
  });

  test('hide cancels timer immediately', () async {
    final s = await SettingsService.load(InMemorySettingsStore());

    fakeAsync((async) {
      final c = ProviderContainer(
        overrides: [settingsServiceProvider.overrideWithValue(s)],
      );
      addTearDown(c.dispose);

      c.read(controlsVisibleProvider.notifier).show();
      expect(c.read(controlsVisibleProvider), true);

      c.read(controlsVisibleProvider.notifier).hide();
      expect(c.read(controlsVisibleProvider), false);

      // After the original auto-hide window passes, state should still be false
      // (no crash from a cancelled timer trying to set state).
      async.elapse(const Duration(milliseconds: 3000));
      expect(c.read(controlsVisibleProvider), false);
    });
  });

  test('show restarts timer', () async {
    final s = await SettingsService.load(InMemorySettingsStore());

    fakeAsync((async) {
      final c = ProviderContainer(
        overrides: [settingsServiceProvider.overrideWithValue(s)],
      );
      addTearDown(c.dispose);

      c.read(controlsVisibleProvider.notifier).show();
      async.elapse(const Duration(milliseconds: 2000)); // 2 s elapsed, not yet hidden
      expect(c.read(controlsVisibleProvider), true);

      c.read(controlsVisibleProvider.notifier).show(); // restart timer
      async.elapse(const Duration(milliseconds: 2000)); // only 2 s of the new window
      expect(c.read(controlsVisibleProvider), true); // still visible

      async.elapse(const Duration(milliseconds: 1001)); // now > 3 s past last show
      expect(c.read(controlsVisibleProvider), false);
    });
  });
}
