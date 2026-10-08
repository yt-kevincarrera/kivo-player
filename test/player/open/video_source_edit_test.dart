import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/queue/queue_undo.dart';
import '../../fakes/fakes.dart';

VideoItem _item(String name, int ms) => VideoItem(
    id: 'id-$name', uri: 'content://A/$name', name: name, folder: 'A',
    durationMs: ms, sizeBytes: 1, dateAddedMs: 0);

final _shown = [
  _item('a.mkv', 1000),
  _item('b.mkv', 2000),
  _item('c.mkv', 3000),
  _item('d.mkv', 4000),
];

void main() {
  Future<ProviderContainer> makeC() async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<(ProviderContainer, CurrentVideoNotifier)> opened({int at = 0}) async {
    final c = await makeC();
    final n = c.read(currentVideoProvider.notifier);
    n.openFromList(_shown[at], _shown);
    return (c, n);
  }

  test('openFromList fills queueDurationsMs parallel to the queue', () async {
    final (c, _) = await opened();
    expect(c.read(currentVideoProvider)!.queueDurationsMs, [1000, 2000, 3000, 4000]);
  });

  test('playOrder is the natural order until edited', () async {
    final (c, _) = await opened();
    final s = c.read(currentVideoProvider)!;
    expect(s.order, isNull);
    expect(s.playOrder, [0, 1, 2, 3]);
    expect(s.orderEdited, isFalse);
  });

  test('reorder moves a card in the play order and records a "moved" undo', () async {
    final (c, n) = await opened();
    n.reorder(1, 3);
    final s = c.read(currentVideoProvider)!;
    expect(s.playOrder, [0, 2, 3, 1]);
    expect(s.orderEdited, isTrue);
    expect(c.read(queueUndoProvider)!.kind, QueueEditKind.moved);
    expect(n.peekNext()!.index, 2);
  });

  test('playNext puts the video right after the current one', () async {
    final (c, n) = await opened();
    n.playNext(3);
    expect(c.read(currentVideoProvider)!.playOrder, [0, 3, 1, 2]);
    expect(n.peekNext()!.index, 3);
    expect(c.read(queueUndoProvider)!.kind, QueueEditKind.playNext);
  });

  test('remove drops a video from the order and next skips it', () async {
    final (c, n) = await opened();
    n.remove(1);
    expect(c.read(currentVideoProvider)!.playOrder, [0, 2, 3]);
    expect(n.peekNext()!.index, 2);
    expect(c.read(queueUndoProvider)!.kind, QueueEditKind.removed);
  });

  test('the current video cannot be removed', () async {
    final (c, n) = await opened(at: 2);
    n.remove(2);
    expect(c.read(currentVideoProvider)!.playOrder, [0, 1, 2, 3]);
    expect(c.read(queueUndoProvider), isNull);
  });

  test('undo restores the previous order and the edited flag', () async {
    final (c, n) = await opened();
    n.remove(1);
    await n.undoQueueEdit();
    final s = c.read(currentVideoProvider)!;
    expect(s.playOrder, [0, 1, 2, 3]);
    expect(s.orderEdited, isFalse);
    expect(c.read(queueUndoProvider), isNull);
  });

  test('undo after moving on to another video does nothing', () async {
    final (c, n) = await opened();
    n.remove(3);
    n.advanceTo(n.peekNext()!);
    expect(c.read(queueUndoProvider), isNull);
    await n.undoQueueEdit();
    expect(c.read(currentVideoProvider)!.playOrder, [0, 1, 2]);
  });

  test('sessionAt carries the edited order, flag and durations', () async {
    final (_, n) = await opened();
    n.remove(2);
    final s = n.sessionAt(1)!;
    expect(s.playOrder, [0, 1, 3]);
    expect(s.orderEdited, isTrue);
    expect(s.queueDurationsMs, [1000, 2000, 3000, 4000]);
  });

  test('turning shuffle on after edits brings removed videos back, undo puts it all back',
      () async {
    final (c, n) = await opened();
    n.remove(1);
    await n.setShuffle(true);
    final shuffled = c.read(currentVideoProvider)!;
    expect(shuffled.playOrder.toSet(), {0, 1, 2, 3});
    expect(shuffled.orderEdited, isFalse);
    expect(c.read(queueUndoProvider)!.kind, QueueEditKind.shuffleReset);

    await n.undoQueueEdit();
    expect(c.read(settingsProvider).shuffle, isFalse);
    final s = c.read(currentVideoProvider)!;
    expect(s.playOrder, [0, 2, 3]);
    expect(s.orderEdited, isTrue);
  });

  test('toggling shuffle on an unedited queue offers no undo', () async {
    final (c, n) = await opened();
    await n.setShuffle(true);
    expect(c.read(queueUndoProvider), isNull);
  });
}
