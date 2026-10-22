import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/end_actions/end_actions.dart';
import 'package:kivo_player/player/open/video_source.dart';
import '../../fakes/fakes.dart';

void main() {
  Future<ProviderContainer> load(InMemorySettingsStore store) async {
    final service = await SettingsService.load(store);
    final c = ProviderContainer(
      overrides: [settingsServiceProvider.overrideWithValue(service)],
    );
    addTearDown(c.dispose);
    c.listen(endActionsProvider, (_, _) {});
    return c;
  }

  void open(ProviderContainer c, String path) {
    c
        .read(currentVideoProvider.notifier)
        .open(
          VideoSession(
            playbackPath: path,
            displayName: path,
            queue: [path],
            index: 0,
          ),
        );
  }

  test(
    'old and invalid settings keep global actions off and use a safe action',
    () {
      final s = KivoSettings.fromMap({'endActionsAfter': 'unknown'});
      expect(s.endActionsGlobal, isFalse);
      expect(s.endActionsTrash, isFalse);
      expect(s.endActionsAfter, 'keepGoing');
    },
  );

  test(
    'global profile survives closing the video, a new queue and app recreation',
    () async {
      final store = InMemorySettingsStore();
      final c = await load(store);
      open(c, 'a');
      final n = c.read(endActionsProvider.notifier);
      await n.setTrash(true);
      await n.setAfter(AfterEnd.closePlayer);
      await n.setGlobal(true);
      c.read(currentVideoProvider.notifier).clear();
      open(c, 'b');
      expect(c.read(endActionsProvider).trash, isTrue);
      expect(c.read(endActionsProvider).after, AfterEnd.closePlayer);
      final restarted = await load(store);
      open(restarted, 'c');
      expect(restarted.read(endActionsProvider).trash, isTrue);
      expect(restarted.read(endActionsProvider).after, AfterEnd.closePlayer);
    },
  );

  test(
    'chip off disables global actions persistently and retains the saved profile',
    () async {
      final store = InMemorySettingsStore();
      final c = await load(store);
      final n = c.read(endActionsProvider.notifier);
      await n.setTrash(true);
      await n.setGlobal(true);
      c.read(afterPendingProvider.notifier).state = AfterEnd.closeApp;
      await n.clear();
      expect(c.read(afterPendingProvider), isNull);
      expect(c.read(endActionsProvider).isActive, isFalse);
      expect(c.read(settingsProvider).endActionsGlobal, isFalse);
      final restarted = await load(store);
      open(restarted, 'b');
      expect(restarted.read(endActionsProvider).isActive, isFalse);
      await restarted
          .read(endActionsProvider.notifier)
          .setGlobal(true, useCurrent: false);
      expect(restarted.read(endActionsProvider).trash, isTrue);
    },
  );

  test(
    'global edits persist, unrelated settings preserve a temporary choice',
    () async {
      final store = InMemorySettingsStore();
      final c = await load(store);
      final n = c.read(endActionsProvider.notifier);
      await n.setGlobal(true);
      await n.setAfter(AfterEnd.restart);
      final restarted = await load(store);
      expect(restarted.read(endActionsProvider).after, AfterEnd.restart);
      await n.setGlobal(false);
      await n.setTrash(true);
      await c
          .read(settingsProvider.notifier)
          .set(c.read(settingsProvider).copyWith(autoplayNext: false));
      expect(c.read(endActionsProvider).trash, isTrue);
      open(c, 'b');
      expect(c.read(endActionsProvider).isActive, isFalse);
    },
  );

  test(
    'saved profile can be configured without arming the current session',
    () async {
      final c = await load(InMemorySettingsStore());
      final n = c.read(endActionsProvider.notifier);
      await n.setSavedTrash(true);
      await n.setSavedAfter(AfterEnd.closeApp);
      expect(c.read(endActionsProvider).isActive, isFalse);
      await n.setGlobal(true, useCurrent: false);
      expect(c.read(endActionsProvider).trash, isTrue);
      expect(c.read(endActionsProvider).after, AfterEnd.closeApp);
    },
  );

  test(
    'settings defaults apply immediately and survive app recreation',
    () async {
      final store = InMemorySettingsStore();
      final c = await load(store);
      final n = c.read(endActionsProvider.notifier);
      await n.setDefaults(trash: true);
      await n.setDefaults(after: AfterEnd.closePlayer);
      expect(c.read(settingsProvider).endActionsGlobal, isTrue);
      expect(c.read(endActionsProvider).trash, isTrue);
      expect(c.read(endActionsProvider).after, AfterEnd.closePlayer);

      final restarted = await load(store);
      open(restarted, 'next');
      expect(restarted.read(endActionsProvider).trash, isTrue);
      expect(restarted.read(endActionsProvider).after, AfterEnd.closePlayer);

      await restarted
          .read(endActionsProvider.notifier)
          .setDefaults(trash: false);
      expect(restarted.read(endActionsProvider).after, AfterEnd.closePlayer);
      await restarted
          .read(endActionsProvider.notifier)
          .setDefaults(after: AfterEnd.keepGoing);
      expect(restarted.read(settingsProvider).endActionsGlobal, isFalse);
      expect(restarted.read(endActionsProvider).isActive, isFalse);
      final disabled = await load(store);
      open(disabled, 'another');
      expect(disabled.read(endActionsProvider).isActive, isFalse);
    },
  );

  test(
    'settings never revive dormant trash or save a temporary player choice',
    () async {
      final c = await load(InMemorySettingsStore());
      final n = c.read(endActionsProvider.notifier);
      await n.setSavedTrash(true);
      await n.setSavedAfter(AfterEnd.closeApp);
      open(c, 'current');
      await n.setTrash(true);
      await n.setAfter(AfterEnd.screenOff);
      final applied = <EndActions>[];
      c.listen(endActionsProvider, (_, next) => applied.add(next));

      await n.setDefaults(after: AfterEnd.closePlayer);
      expect(c.read(settingsProvider).endActionsGlobal, isTrue);
      expect(c.read(settingsProvider).endActionsTrash, isFalse);
      expect(c.read(endActionsProvider).trash, isFalse);
      expect(c.read(endActionsProvider).after, AfterEnd.closePlayer);
      expect(applied, hasLength(1));
      expect(applied.single.trash, isFalse);
    },
  );

  test(
    'settings restart clears trash without restoring it on the next choice',
    () async {
      final c = await load(InMemorySettingsStore());
      final n = c.read(endActionsProvider.notifier);
      await n.setDefaults(trash: true, after: AfterEnd.closePlayer);
      c.read(afterPendingProvider.notifier).state = AfterEnd.closePlayer;

      await n.setDefaults(after: AfterEnd.restart);
      expect(c.read(afterPendingProvider), isNull);
      expect(c.read(settingsProvider).endActionsTrash, isFalse);
      expect(c.read(endActionsProvider).trash, isFalse);
      await n.setDefaults(after: AfterEnd.closeApp);
      expect(c.read(endActionsProvider).trash, isFalse);
      expect(c.read(endActionsProvider).after, AfterEnd.closeApp);
    },
  );
}
