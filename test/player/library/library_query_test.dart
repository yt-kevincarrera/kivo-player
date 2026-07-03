import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/library_query.dart';

VideoItem v(String name, String folder) => VideoItem(
    id: name, uri: 'content://$folder/$name', name: name, folder: folder,
    durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);

void main() {
  test('groupByFolder groups and natural-sorts by name', () {
    final items = [v('clip2.mp4', 'A'), v('clip10.mp4', 'A'), v('z.mp4', 'B'), v('clip1.mp4', 'A')];
    final g = groupByFolder(items);
    expect(g.keys.toSet(), {'A', 'B'});
    expect(g['A']!.map((e) => e.name).toList(), ['clip1.mp4', 'clip2.mp4', 'clip10.mp4']);
    expect(g['B']!.map((e) => e.name).toList(), ['z.mp4']);
  });

}
