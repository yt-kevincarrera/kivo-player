import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/open/video_source.dart';

void main() {
  ProviderContainer makeC() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

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
