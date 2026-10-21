import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/end_actions/end_actions.dart';
import 'package:kivo_player/player/open/video_source.dart';
import '../../fakes/fakes.dart';

void main() {
  EndPlan plan({
    bool trash = true,
    AfterEnd after = AfterEnd.keepGoing,
    bool eligible = true,
    bool repeatVideo = false,
    bool loopActive = false,
    bool autoplayGo = true,
  }) =>
      planEnd(
        actions: EndActions(trash: trash, after: after),
        eligible: eligible,
        repeatVideo: repeatVideo,
        loopActive: loopActive,
        autoplayGo: autoplayGo,
      );

  group('planEnd', () {
    test('an active A-B loop plans nothing', () {
      final p = plan(after: AfterEnd.closeApp, loopActive: true);
      expect(p.trash, isFalse);
      expect(p.advance, isFalse);
      expect(p.after, isNull);
    });

    test('repeat-video never trashes', () {
      expect(plan(repeatVideo: true).trash, isFalse);
    });

    test('restart never deletes or advances, even with autoplay off', () {
      final p = plan(after: AfterEnd.restart, autoplayGo: false);
      expect(p.restart, isTrue);
      expect(p.trash, isFalse);
      expect(p.advance, isFalse);
      expect(p.after, isNull);
    });

    test('sleep and A-B loop suppress restart', () {
      expect(plan(after: AfterEnd.restart, loopActive: true).restart, isFalse);
      expect(planEnd(actions: const EndActions(after: AfterEnd.restart),
        eligible: true, repeatVideo: false, loopActive: false,
        autoplayGo: false, sleepStop: true).restart, isFalse);
    });

    test('a video outside the library is never trashed', () {
      expect(plan(eligible: false).trash, isFalse);
    });

    test('trash off plans no trash', () {
      expect(plan(trash: false).trash, isFalse);
    });

    test('keepGoing mirrors autoplay', () {
      expect(plan().advance, isTrue);
      expect(plan().after, isNull);
      expect(plan(autoplayGo: false).advance, isFalse);
      expect(plan(autoplayGo: false).trash, isTrue);
    });

    test('any other action stops the queue and runs instead', () {
      for (final a in [AfterEnd.closePlayer, AfterEnd.closeApp, AfterEnd.screenOff]) {
        final p = plan(after: a);
        expect(p.advance, isFalse, reason: '$a');
        expect(p.after, a);
        expect(p.trash, isTrue);
      }
    });

    test('the sleep timer stopping still runs the action', () {
      final p = plan(after: AfterEnd.screenOff, autoplayGo: false);
      expect(p.after, AfterEnd.screenOff);
    });
  });

  group('endActionsProvider', () {
    Future<ProviderContainer> make() async {
      final s = await SettingsService.load(InMemorySettingsStore());
      final c = ProviderContainer(overrides: [
        settingsServiceProvider.overrideWithValue(s),
      ]);
      addTearDown(c.dispose);
      c.listen(endActionsProvider, (_, _) {});
      return c;
    }

    VideoSession session(List<String> queue, int index) => VideoSession(
          playbackPath: queue[index],
          displayName: queue[index],
          queue: queue,
          queueNames: queue,
          index: index,
        );

    test('isActive reflects trash or a non-default action', () {
      expect(const EndActions().isActive, isFalse);
      expect(const EndActions(trash: true).isActive, isTrue);
      expect(const EndActions(after: AfterEnd.closeApp).isActive, isTrue);
    });

    test('moving along the same queue keeps the choice', () async {
      final c = await make();
      final q = ['a.mp4', 'b.mp4'];
      c.read(currentVideoProvider.notifier).open(session(q, 0));
      c.read(endActionsProvider.notifier).setTrash(true);
      c.read(endActionsProvider.notifier).setAfter(AfterEnd.closeApp);
      c.read(currentVideoProvider.notifier).advanceTo(
          c.read(currentVideoProvider.notifier).sessionAt(1)!);
      expect(c.read(endActionsProvider).trash, isTrue);
      expect(c.read(endActionsProvider).after, AfterEnd.closeApp);
    });

    test('opening a different queue forgets it', () async {
      final c = await make();
      c.read(currentVideoProvider.notifier).open(session(['a.mp4', 'b.mp4'], 0));
      c.read(endActionsProvider.notifier).setTrash(true);
      c.read(currentVideoProvider.notifier).open(session(['x.mp4', 'y.mp4'], 0));
      expect(c.read(endActionsProvider).isActive, isFalse);
    });

    test('changing the choice mid-countdown applies to that ending', () async {
      final c = await make();
      final s = session(['a.mp4', 'b.mp4'], 0);
      c.read(currentVideoProvider.notifier).open(s);
      const item = VideoItem(
          id: '1', uri: 'a.mp4', name: 'a.mp4', folder: '',
          durationMs: 0, sizeBytes: 0, dateAddedMs: 0);
      c.read(endTrashProvider.notifier).state = EndTrash(s, item);
      c.read(afterPendingProvider.notifier).state = AfterEnd.closeApp;

      c.read(endActionsProvider.notifier).setTrash(false);
      expect(c.read(endTrashProvider), isNull);
      c.read(endActionsProvider.notifier).setAfter(AfterEnd.screenOff);
      expect(c.read(afterPendingProvider), isNull);

      c.read(endTrashProvider.notifier).state = EndTrash(s, item);
      c.read(afterPendingProvider.notifier).state = AfterEnd.closeApp;
      c.read(endActionsProvider.notifier).clear(); // the chip's ✕
      expect(c.read(endTrashProvider), isNull);
      expect(c.read(afterPendingProvider), isNull);
    });
  });
}
