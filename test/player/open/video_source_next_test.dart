import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/open/video_source.dart';

import '../../fakes/fakes.dart';

VideoItem _item(String name, String folder) => VideoItem(
    id: name, uri: 'content://$folder/$name', name: name, folder: folder,
    durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);

void main() {
  // Every existing test relies on the natural-order behavior that
  // repeatMode: off / shuffle: false gives — that's the default, so these
  // stay byte-for-byte the same as before repeat/shuffle existed. Tests that
  // want a different mode pass it explicitly.
  Future<ProviderContainer> makeC({
    String repeatMode = 'off',
    bool shuffle = false,
    Random? random,
  }) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    await svc.update(svc.current.copyWith(repeatMode: repeatMode, shuffle: shuffle));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      if (random != null) queueRandomProvider.overrideWithValue(random),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('openFromList keeps the displayed order verbatim (not re-sorted, not folder-scoped)', () async {
    final c = await makeC();
    final n = c.read(currentVideoProvider.notifier);
    // As shown in a flat library view: mixed folders, NOT alphabetical.
    final shown = [
      _item('z.mkv', 'B'), // the tapped video
      _item('a.mkv', 'A'),
      _item('m.mkv', 'B'),
    ];
    n.openFromList(shown[0], shown);
    final s = c.read(currentVideoProvider)!;
    expect(s.queue, ['content://B/z.mkv', 'content://A/a.mkv', 'content://B/m.mkv']);
    expect(s.queueNames, ['z.mkv', 'a.mkv', 'm.mkv']);
    expect(s.index, 0);
    expect(s.folder, 'B');
    // Autoplay follows the displayed order, crossing folders — not just folder B.
    final next = n.peekNext();
    expect(next!.playbackPath, 'content://A/a.mkv');
    expect(next.index, 1);
  });

  test('openFromList starting mid-list sets the right index and can reach the end', () async {
    final c = await makeC();
    final n = c.read(currentVideoProvider.notifier);
    final shown = [_item('1.mkv', 'A'), _item('2.mkv', 'A'), _item('3.mkv', 'A')];
    n.openFromList(shown[1], shown); // tap the middle one
    expect(c.read(currentVideoProvider)!.index, 1);
    final next = n.peekNext()!;
    expect(next.playbackPath, 'content://A/3.mkv');
    n.advanceTo(next);
    expect(n.peekNext(), isNull); // now at the last
  });

  test('[at] pins the position when the same video appears twice', () async {
    final c = await makeC();
    final n = c.read(currentVideoProvider.notifier);
    // A playlist may legitimately hold one video twice. Without [at], the URI
    // search resolves both copies to the first, so tapping the last one would
    // start the queue at position 0 and autoplay would walk it all over again.
    final dup = _item('1.mkv', 'A');
    final shown = [dup, _item('2.mkv', 'A'), dup];
    n.openFromList(dup, shown, at: 2);
    expect(c.read(currentVideoProvider)!.index, 2);
    expect(n.peekNext(), isNull); // it IS the last entry
  });

  test('an out-of-range [at] falls back to the URI search', () async {
    final c = await makeC();
    final n = c.read(currentVideoProvider.notifier);
    final shown = [_item('1.mkv', 'A'), _item('2.mkv', 'A')];
    n.openFromList(shown[1], shown, at: 9);
    expect(c.read(currentVideoProvider)!.index, 1);
  });

  test('peekNext returns the next session or null at the end', () async {
    final c = await makeC();
    final n = c.read(currentVideoProvider.notifier);
    n.open(const VideoSession(
      playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv',
      queue: ['/v/ep1.mkv', '/v/ep2.mkv'], queueNames: ['ep1.mkv', 'ep2.mkv'],
      index: 0, folder: 'Series',
    ));
    final next = n.peekNext();
    expect(next, isNotNull);
    expect(next!.playbackPath, '/v/ep2.mkv');
    expect(next.displayName, 'ep2.mkv');
    expect(next.index, 1);
    expect(next.folder, 'Series');

    n.advanceTo(next);
    expect(c.read(currentVideoProvider)!.index, 1);
    expect(c.read(currentVideoProvider.notifier).peekNext(), isNull); // last item
  });

  test('peekNext is null for a single-item (file-picker) queue', () async {
    final c = await makeC();
    final n = c.read(currentVideoProvider.notifier);
    n.openPath('/v/solo.mkv');
    expect(n.peekNext(), isNull);
  });

  test('peekNext falls back to basename when queueNames is short', () async {
    final c = await makeC();
    final n = c.read(currentVideoProvider.notifier);
    n.open(const VideoSession(
      playbackPath: '/v/a.mkv', displayName: 'a.mkv',
      queue: ['/v/a.mkv', '/v/b.mkv'], queueNames: [], index: 0,
    ));
    expect(n.peekNext()!.displayName, 'b.mkv');
  });

  group('repeatMode', () {
    final three = [_item('1.mkv', 'A'), _item('2.mkv', 'A'), _item('3.mkv', 'A')];

    test('list: wraps from the last video back to the first', () async {
      final c = await makeC(repeatMode: 'list');
      final n = c.read(currentVideoProvider.notifier);
      n.openFromList(three[2], three); // start at the last
      final next = n.peekNext();
      expect(next, isNotNull);
      expect(next!.index, 0);
      expect(next.playbackPath, 'content://A/1.mkv');
    });

    test('list: mid-queue still just walks forward', () async {
      final c = await makeC(repeatMode: 'list');
      final n = c.read(currentVideoProvider.notifier);
      n.openFromList(three[0], three);
      expect(n.peekNext()!.index, 1);
    });

    test('video: peekNext returns the SAME session, not the next one', () async {
      final c = await makeC(repeatMode: 'video');
      final n = c.read(currentVideoProvider.notifier);
      n.openFromList(three[1], three); // start in the middle
      final next = n.peekNext();
      expect(next, isNotNull);
      expect(next!.index, 1);
      expect(next.playbackPath, 'content://A/2.mkv');
    });

    test('video: also loops the last video onto itself, not off the end', () async {
      final c = await makeC(repeatMode: 'video');
      final n = c.read(currentVideoProvider.notifier);
      n.openFromList(three[2], three);
      final next = n.peekNext();
      expect(next, isNotNull);
      expect(next!.index, 2);
    });

    test('off (default): still null at the end — unchanged from before this feature', () async {
      final c = await makeC(); // repeatMode defaults to off
      final n = c.read(currentVideoProvider.notifier);
      n.openFromList(three[2], three);
      expect(n.peekNext(), isNull);
    });
  });

  group('shuffle', () {
    test('a 2-item queue: peekNext is deterministically the other video (only one possible order)', () async {
      final c = await makeC(shuffle: true, random: Random(1));
      final n = c.read(currentVideoProvider.notifier);
      final two = [_item('1.mkv', 'A'), _item('2.mkv', 'A')];
      n.openFromList(two[0], two);
      final s = c.read(currentVideoProvider)!;
      expect(s.order, [0, 1]); // current (0) first — the only permutation possible
      expect(n.peekNext()!.playbackPath, 'content://A/2.mkv');
    });

    test('the shuffled order is generated once and reused across advances, not re-rolled', () async {
      final c = await makeC(shuffle: true, random: Random(3));
      final n = c.read(currentVideoProvider.notifier);
      final five = [for (var i = 0; i < 5; i++) _item('$i.mkv', 'A')];
      n.openFromList(five[0], five);
      final order = c.read(currentVideoProvider)!.order;
      expect(order, isNotNull);
      // Walk the whole order via peekNext/advanceTo: it must exactly match
      // the permutation drawn once at open time — never a fresh draw.
      for (var i = 1; i < order!.length; i++) {
        final next = n.peekNext()!;
        expect(next.index, order[i]);
        n.advanceTo(next);
        expect(c.read(currentVideoProvider)!.order, order); // unchanged
      }
    });

    test('setShuffle(true) draws a fresh permutation with the current video first, keeping the index', () async {
      final c = await makeC(random: Random(9));
      final n = c.read(currentVideoProvider.notifier);
      final four = [for (var i = 0; i < 4; i++) _item('$i.mkv', 'A')];
      n.openFromList(four[2], four); // start at index 2, shuffle off
      expect(c.read(currentVideoProvider)!.order, isNull);

      await n.setShuffle(true);
      final s = c.read(currentVideoProvider)!;
      expect(s.index, 2); // unchanged
      expect(s.order, isNotNull);
      expect(s.order!.first, 2); // current video first
      expect(s.order!.toSet(), {0, 1, 2, 3});
      expect(c.read(settingsProvider).shuffle, true); // persisted too
    });

    test('setShuffle(false) drops the order — natural order resumes, index unchanged', () async {
      final c = await makeC(shuffle: true, random: Random(4));
      final n = c.read(currentVideoProvider.notifier);
      final four = [for (var i = 0; i < 4; i++) _item('$i.mkv', 'A')];
      n.openFromList(four[1], four);
      expect(c.read(currentVideoProvider)!.order, isNotNull);

      await n.setShuffle(false);
      final s = c.read(currentVideoProvider)!;
      expect(s.order, isNull);
      expect(s.index, 1); // unchanged
      expect(c.read(settingsProvider).shuffle, false);
    });

    test('a one-item queue with shuffle on behaves exactly like shuffle off', () async {
      final c = await makeC(shuffle: true, random: Random(2));
      final n = c.read(currentVideoProvider.notifier);
      n.openFromList(_item('solo.mkv', 'A'), [_item('solo.mkv', 'A')]);
      expect(n.peekNext(), isNull);
    });

    group('open() applies shuffle directly (the vault path, and any other '
        'caller that builds its own multi-item session)', () {
      test('shuffle on: a direct multi-item open() draws an order — current first, permutation complete', () async {
        final c = await makeC(shuffle: true, random: Random(5));
        final n = c.read(currentVideoProvider.notifier);
        n.open(const VideoSession(
          playbackPath: '/v/2.mkv',
          displayName: '2.mkv',
          queue: ['/v/1.mkv', '/v/2.mkv', '/v/3.mkv', '/v/4.mkv'],
          index: 1,
        ));
        final s = c.read(currentVideoProvider)!;
        expect(s.order, isNotNull);
        expect(s.order!.first, 1); // current video first
        expect(s.order!.toSet(), {0, 1, 2, 3});
      });

      test('shuffle on: a direct open() with a 1-item queue stays null (shuffle is a no-op)', () async {
        final c = await makeC(shuffle: true, random: Random(6));
        final n = c.read(currentVideoProvider.notifier);
        n.open(const VideoSession(
          playbackPath: '/v/solo.mkv',
          displayName: 'solo.mkv',
          queue: ['/v/solo.mkv'],
          index: 0,
        ));
        expect(c.read(currentVideoProvider)!.order, isNull);
      });

      test('shuffle off: a direct multi-item open() leaves order null', () async {
        final c = await makeC(); // shuffle defaults to false
        final n = c.read(currentVideoProvider.notifier);
        n.open(const VideoSession(
          playbackPath: '/v/1.mkv',
          displayName: '1.mkv',
          queue: ['/v/1.mkv', '/v/2.mkv', '/v/3.mkv'],
          index: 0,
        ));
        expect(c.read(currentVideoProvider)!.order, isNull);
      });

      test('a caller-supplied order is never overwritten, even with shuffle on', () async {
        final c = await makeC(shuffle: true, random: Random(7));
        final n = c.read(currentVideoProvider.notifier);
        n.open(const VideoSession(
          playbackPath: '/v/1.mkv',
          displayName: '1.mkv',
          queue: ['/v/1.mkv', '/v/2.mkv', '/v/3.mkv'],
          index: 0,
          order: [2, 0, 1],
        ));
        expect(c.read(currentVideoProvider)!.order, [2, 0, 1]);
      });
    });
  });
}
