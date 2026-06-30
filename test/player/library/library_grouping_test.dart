import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/library_grouping.dart';

VideoItem at(String name, int ms) => VideoItem(
    id: name, uri: 'content://$name', name: name, folder: 'F',
    durationMs: 1000, sizeBytes: 1, dateAddedMs: ms);

void main() {
  final now = DateTime(2026, 6, 30, 12); // Tue 30 Jun 2026
  int day(int y, int m, int d) => DateTime(y, m, d, 9).millisecondsSinceEpoch;

  test('groups by relative day, newest first', () {
    final items = [
      at('today.mp4', day(2026, 6, 30)),
      at('yest.mp4', day(2026, 6, 29)),
      at('thisyear.mp4', day(2026, 6, 12)),
      at('old.mp4', day(2024, 3, 5)),
    ];
    final s = groupByDay(items, now);
    expect(s.map((e) => e.label).toList(), ['Hoy', 'Ayer', '12 jun', 'mar 2024']);
    expect(s.first.items.single.name, 'today.mp4');
  });

  test('same-day items share a section', () {
    final items = [at('a.mp4', day(2026, 6, 30) + 100), at('b.mp4', day(2026, 6, 30))];
    final s = groupByDay(items, now);
    expect(s.length, 1);
    expect(s.first.label, 'Hoy');
    expect(s.first.items.map((e) => e.name).toList(), ['a.mp4', 'b.mp4']); // newest first
  });
}
