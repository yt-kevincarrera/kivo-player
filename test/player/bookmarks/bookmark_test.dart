import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/bookmarks/bookmark.dart';

void main() {
  group('Bookmark', () {
    test('round-trips through toMap/fromMap', () {
      const b = Bookmark(positionMs: 12345, name: 'Golazo', createdAtMs: 999);
      final back = Bookmark.fromMap(b.toMap());
      expect(back, b);
    });

    test('tolerates the Map<dynamic,dynamic> Hive hands back on read', () {
      final Map<dynamic, dynamic> raw = {'p': 1000, 'n': 'Intro', 'c': 500};
      final b = Bookmark.fromMap(raw);
      expect(b.positionMs, 1000);
      expect(b.name, 'Intro');
      expect(b.createdAtMs, 500);
    });

    test('missing keys fall back rather than throw', () {
      final b = Bookmark.fromMap(const {});
      expect(b.positionMs, 0);
      expect(b.name, '');
      expect(b.createdAtMs, 0);
    });

    test('unknown keys are ignored', () {
      final b = Bookmark.fromMap(const {'p': 10, 'n': 'x', 'c': 1, 'z': 'huh'});
      expect(b.positionMs, 10);
      expect(b.name, 'x');
      expect(b.createdAtMs, 1);
    });

    test('value equality does not consider identity', () {
      const a = Bookmark(positionMs: 1, name: 'a', createdAtMs: 1);
      const b = Bookmark(positionMs: 1, name: 'a', createdAtMs: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith replaces only the name', () {
      const b = Bookmark(positionMs: 5, name: '', createdAtMs: 7);
      final renamed = b.copyWith(name: 'Escena final');
      expect(renamed.name, 'Escena final');
      expect(renamed.positionMs, 5);
      expect(renamed.createdAtMs, 7);
    });
  });

  group('bookmarkMarks', () {
    const total = Duration(minutes: 10);

    test('empty list produces no marks', () {
      expect(bookmarkMarks(const [], total), isEmpty);
    });

    test('zero duration produces no marks even with bookmarks present', () {
      const bookmarks = [Bookmark(positionMs: 1000, name: '', createdAtMs: 0)];
      expect(bookmarkMarks(bookmarks, Duration.zero), isEmpty);
    });

    test('a bookmark at the very start produces no mark', () {
      const bookmarks = [Bookmark(positionMs: 0, name: '', createdAtMs: 0)];
      expect(bookmarkMarks(bookmarks, total), isEmpty);
    });

    test('a bookmark at or past the end is dropped', () {
      final bookmarks = [
        Bookmark(positionMs: total.inMilliseconds, name: '', createdAtMs: 0),
        Bookmark(positionMs: total.inMilliseconds + 500, name: '', createdAtMs: 0),
      ];
      expect(bookmarkMarks(bookmarks, total), isEmpty);
    });

    test('mid-video bookmarks produce their fraction of the total', () {
      const bookmarks = [
        Bookmark(positionMs: 60000, name: '', createdAtMs: 0), // 1 min of 10
        Bookmark(positionMs: 300000, name: '', createdAtMs: 0), // 5 min of 10
      ];
      final marks = bookmarkMarks(bookmarks, total);
      expect(marks, [closeTo(0.1, 1e-9), closeTo(0.5, 1e-9)]);
    });
  });
}
