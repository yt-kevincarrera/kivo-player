import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/open/video_source.dart';

VideoItem _item(String name, String folder) => VideoItem(
    id: name, uri: 'content://$folder/$name', name: name, folder: folder,
    durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);

void main() {
  ProviderContainer makeC() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('openFromList keeps the displayed order verbatim (not re-sorted, not folder-scoped)', () {
    final c = makeC();
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

  test('openFromList starting mid-list sets the right index and can reach the end', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    final shown = [_item('1.mkv', 'A'), _item('2.mkv', 'A'), _item('3.mkv', 'A')];
    n.openFromList(shown[1], shown); // tap the middle one
    expect(c.read(currentVideoProvider)!.index, 1);
    final next = n.peekNext()!;
    expect(next.playbackPath, 'content://A/3.mkv');
    n.advanceTo(next);
    expect(n.peekNext(), isNull); // now at the last
  });

  test('[at] pins the position when the same video appears twice', () {
    final c = makeC();
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

  test('an out-of-range [at] falls back to the URI search', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    final shown = [_item('1.mkv', 'A'), _item('2.mkv', 'A')];
    n.openFromList(shown[1], shown, at: 9);
    expect(c.read(currentVideoProvider)!.index, 1);
  });

  test('peekNext returns the next session or null at the end', () {
    final c = makeC();
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

  test('peekNext is null for a single-item (file-picker) queue', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    n.openPath('/v/solo.mkv');
    expect(n.peekNext(), isNull);
  });

  test('peekNext falls back to basename when queueNames is short', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    n.open(const VideoSession(
      playbackPath: '/v/a.mkv', displayName: 'a.mkv',
      queue: ['/v/a.mkv', '/v/b.mkv'], queueNames: [], index: 0,
    ));
    expect(n.peekNext()!.displayName, 'b.mkv');
  });
}
