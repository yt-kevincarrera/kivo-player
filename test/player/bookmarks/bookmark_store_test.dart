import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kivo_player/player/bookmarks/bookmark.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';

const _b1 = Bookmark(positionMs: 1000, name: 'Intro', createdAtMs: 1);
const _b2 = Bookmark(positionMs: 5000, name: '', createdAtMs: 2);

void main() {
  group('InMemoryBookmarkStore', () {
    test('forVideo returns nothing for a key never written', () {
      final s = InMemoryBookmarkStore();
      expect(s.forVideo('nope.mp4'), isEmpty);
    });

    test('put then forVideo round-trips the list, in order', () async {
      final s = InMemoryBookmarkStore();
      await s.put('ep1.mkv', const [_b1, _b2]);
      expect(s.forVideo('ep1.mkv'), [_b1, _b2]);
    });

    test('put replaces the previous list for that key rather than appending', () async {
      final s = InMemoryBookmarkStore();
      await s.put('ep1.mkv', const [_b1]);
      await s.put('ep1.mkv', const [_b2]);
      expect(s.forVideo('ep1.mkv'), [_b2]);
    });

    test('remove clears only the given key', () async {
      final s = InMemoryBookmarkStore();
      await s.put('ep1.mkv', const [_b1]);
      await s.put('ep2.mkv', const [_b2]);
      await s.remove('ep1.mkv');
      expect(s.forVideo('ep1.mkv'), isEmpty);
      expect(s.forVideo('ep2.mkv'), [_b2]);
    });

    test('removing a key that was never written is a no-op, not a throw', () async {
      final s = InMemoryBookmarkStore();
      await s.remove('nope.mp4');
      expect(s.forVideo('nope.mp4'), isEmpty);
    });

    test('rename moves the bookmarks from the old key to the new one', () async {
      final s = InMemoryBookmarkStore();
      await s.put('old.mp4', const [_b1, _b2]);
      await s.rename('old.mp4', 'new.mp4');
      expect(s.forVideo('old.mp4'), isEmpty);
      expect(s.forVideo('new.mp4'), [_b1, _b2]);
    });

    test('renaming a key with no bookmarks is a no-op', () async {
      final s = InMemoryBookmarkStore();
      await s.rename('old.mp4', 'new.mp4');
      expect(s.forVideo('new.mp4'), isEmpty);
    });

    test('forVideo returns a copy, not the live list', () async {
      final s = InMemoryBookmarkStore();
      await s.put('ep1.mkv', const [_b1]);
      final list = s.forVideo('ep1.mkv');
      list.add(_b2);
      expect(s.forVideo('ep1.mkv'), [_b1]);
    });

    test('all() returns every video with bookmarks, keyed by video', () async {
      final s = InMemoryBookmarkStore();
      await s.put('ep1.mkv', const [_b1]);
      await s.put('ep2.mkv', const [_b2]);
      final all = s.all();
      expect(all.keys, unorderedEquals(['ep1.mkv', 'ep2.mkv']));
      expect(all['ep1.mkv'], [_b1]);
      expect(all['ep2.mkv'], [_b2]);
    });

    test('all() on an empty store is an empty map', () {
      expect(InMemoryBookmarkStore().all(), isEmpty);
    });
  });

  group('HiveBookmarkStore', () {
    late Directory tmp;
    late Box box;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('kivo_bookmarks_hive');
      Hive.init(tmp.path);
      box = await Hive.openBox('bookmarks');
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      tmp.deleteSync(recursive: true);
    });

    test('all() returns every video with bookmarks, keyed by video', () async {
      final s = HiveBookmarkStore(box);
      await s.put('ep1.mkv', const [_b1]);
      await s.put('ep2.mkv', const [_b2]);

      final all = s.all();
      expect(all.keys, unorderedEquals(['ep1.mkv', 'ep2.mkv']));
      expect(all['ep1.mkv'], [_b1]);
      expect(all['ep2.mkv'], [_b2]);
    });

    // A key whose raw stored value isn't the shape put() ever writes —
    // e.g. a foreign write, or a future format this build doesn't know —
    // must be skipped, the same tolerance HivePlaylistStore.all() has for a
    // non-Map row.
    test('all() skips a key whose raw value is not a List', () async {
      final s = HiveBookmarkStore(box);
      await s.put('good.mkv', const [_b1]);
      await box.put('corrupt.mkv', 'not a list');

      final all = s.all();
      expect(all.keys, ['good.mkv']);
    });

    test('all() on an empty box is an empty map', () {
      expect(HiveBookmarkStore(box).all(), isEmpty);
    });
  });
}
