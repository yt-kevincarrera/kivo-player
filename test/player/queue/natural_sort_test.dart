import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/queue/natural_sort.dart';

void main() {
  test('orders episode numbers numerically, not lexically', () {
    final names = ['ep2.mkv', 'ep10.mkv', 'ep1.mkv'];
    names.sort(naturalCompare);
    expect(names, ['ep1.mkv', 'ep2.mkv', 'ep10.mkv']);
  });

  test('case-insensitive', () {
    expect(naturalCompare('Apple', 'apple') == 0, isFalse); // stable but defined
    final l = ['B.mkv', 'a.mkv'];
    l.sort(naturalCompare);
    expect(l.first, 'a.mkv');
  });
}
