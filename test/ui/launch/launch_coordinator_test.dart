import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/continue_watching.dart';
import 'package:kivo_player/ui/launch/launch_coordinator.dart';

VideoItem _v(String id, String folder, {String? name}) => VideoItem(
      id: id,
      uri: 'content://media/external/video/media/$id',
      name: name ?? 'video$id.mp4',
      folder: folder,
      durationMs: 600000,
      sizeBytes: 1,
      dateAddedMs: 0,
    );

void main() {
  group('continueEntriesFor', () {
    test('the first three, with a formatted position', () {
      final items = [
        for (var i = 1; i <= 5; i++)
          ContinueItem(_v('$i', 'Series'), 754, 0.4),
      ];
      final entries = continueEntriesFor(items);
      expect(entries.map((e) => e.id), ['1', '2', '3']);
      expect(entries.first.position, '12:34');
      expect(entries.first.fraction, 0.4);
      expect(entries.first.uri, endsWith('/1'));
    });

    test('nothing in progress, nothing to show', () {
      expect(continueEntriesFor(const []), isEmpty);
    });
  });

  group('resolveLaunch', () {
    final index = [
      _v('1', 'Series'),
      _v('2', 'Movies'),
      _v('3', 'Series'),
      _v('4', 'Series'),
    ];

    test('opens with its folder as the queue, in library order', () {
      final t = resolveLaunch('3', index)!;
      expect(t.video.id, '3');
      expect(t.queue.map((v) => v.id), ['1', '3', '4']);
    });

    // Deleted or moved to the Vault since the shortcut was made.
    test('a video that is gone is ignored quietly', () {
      expect(resolveLaunch('99', index), isNull);
    });
  });
}
