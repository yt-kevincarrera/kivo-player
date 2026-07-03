import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/open/video_source.dart';

VideoItem _item(String name, String folder) => VideoItem(
    id: 'id-$name', uri: 'content://$folder/$name', name: name, folder: folder,
    durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);

void main() {
  ProviderContainer makeC() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('openFromList populates queueIds parallel to queue/queueNames', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    final shown = [_item('a.mkv', 'A'), _item('b.mkv', 'A'), _item('c.mkv', 'A')];
    n.openFromList(shown[0], shown);
    final s = c.read(currentVideoProvider)!;
    expect(s.queueIds, ['id-a.mkv', 'id-b.mkv', 'id-c.mkv']);
    expect(s.queueIds.length, s.queue.length);
  });

  test('sessionAt builds any index and null out of range; carries ids/names/folder', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    final shown = [_item('a.mkv', 'A'), _item('b.mkv', 'A'), _item('c.mkv', 'A')];
    n.openFromList(shown[0], shown);
    final s2 = n.sessionAt(2)!;
    expect(s2.playbackPath, 'content://A/c.mkv');
    expect(s2.displayName, 'c.mkv');
    expect(s2.index, 2);
    expect(s2.queueIds, ['id-a.mkv', 'id-b.mkv', 'id-c.mkv']);
    expect(s2.folder, 'A');
    expect(n.sessionAt(3), isNull);
    expect(n.sessionAt(-1), isNull);
  });

  test('peekNext still works (delegates to sessionAt)', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    final shown = [_item('a.mkv', 'A'), _item('b.mkv', 'A')];
    n.openFromList(shown[0], shown);
    expect(n.peekNext()!.playbackPath, 'content://A/b.mkv');
    n.advanceTo(n.peekNext()!);
    expect(n.peekNext(), isNull);
  });
}
