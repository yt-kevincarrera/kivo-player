import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/bookmarks/bookmark.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/bookmarks/bookmarks_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';

VideoSession _session(String name) => VideoSession(
      playbackPath: '/v/$name',
      displayName: name,
      queue: ['/v/$name'],
      index: 0,
    );

ProviderContainer _c(BookmarkStore store) => ProviderContainer(
      overrides: [bookmarkStoreProvider.overrideWithValue(store)],
    );

void main() {
  test('no video open means no bookmarks', () {
    final c = _c(InMemoryBookmarkStore());
    addTearDown(c.dispose);
    expect(c.read(bookmarksProvider), isEmpty);
  });

  test('opening a video loads its stored bookmarks, sorted by position', () {
    final store = InMemoryBookmarkStore();
    store.put('a.mkv', const [
      Bookmark(positionMs: 5000, name: 'Late', createdAtMs: 1),
      Bookmark(positionMs: 1000, name: 'Early', createdAtMs: 2),
    ]);
    final c = _c(store);
    addTearDown(c.dispose);

    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));

    expect(
      c.read(bookmarksProvider).map((b) => b.name),
      ['Early', 'Late'],
    );
  });

  test('add updates state synchronously, before the store write lands', () async {
    final c = _c(InMemoryBookmarkStore());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));

    final future = c.read(bookmarksProvider.notifier).add(2000);
    // No await yet — state must already reflect the addition.
    expect(c.read(bookmarksProvider), hasLength(1));
    expect(c.read(bookmarksProvider).single.positionMs, 2000);
    expect(c.read(bookmarksProvider).single.name, '');

    await future;
  });

  test('add keeps the list sorted by position regardless of add order', () async {
    final c = _c(InMemoryBookmarkStore());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));

    await c.read(bookmarksProvider.notifier).add(9000);
    await c.read(bookmarksProvider.notifier).add(1000);
    await c.read(bookmarksProvider.notifier).add(5000);

    expect(
      c.read(bookmarksProvider).map((b) => b.positionMs),
      [1000, 5000, 9000],
    );
  });

  test('add persists to the store under the video key', () async {
    final store = InMemoryBookmarkStore();
    final c = _c(store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));

    await c.read(bookmarksProvider.notifier).add(4000);

    expect(store.forVideo('a.mkv').single.positionMs, 4000);
  });

  test('add returns the created bookmark', () async {
    final c = _c(InMemoryBookmarkStore());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));

    final b = await c.read(bookmarksProvider.notifier).add(3000);
    expect(b.positionMs, 3000);
    expect(b.name, '');
  });

  test('rename sets the name of the bookmark at that index and persists', () async {
    final store = InMemoryBookmarkStore();
    final c = _c(store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));
    await c.read(bookmarksProvider.notifier).add(1000);

    await c.read(bookmarksProvider.notifier).rename(0, 'Golazo');

    expect(c.read(bookmarksProvider).single.name, 'Golazo');
    expect(store.forVideo('a.mkv').single.name, 'Golazo');
  });

  test('rename with an out-of-range index is a no-op', () async {
    final c = _c(InMemoryBookmarkStore());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));
    await c.read(bookmarksProvider.notifier).add(1000);

    await c.read(bookmarksProvider.notifier).rename(5, 'nope');

    expect(c.read(bookmarksProvider).single.name, '');
  });

  test('removeAt removes the bookmark at that index and persists', () async {
    final store = InMemoryBookmarkStore();
    final c = _c(store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));
    await c.read(bookmarksProvider.notifier).add(1000);
    await c.read(bookmarksProvider.notifier).add(2000);

    await c.read(bookmarksProvider.notifier).removeAt(0);

    expect(c.read(bookmarksProvider).map((b) => b.positionMs), [2000]);
    expect(store.forVideo('a.mkv').map((b) => b.positionMs), [2000]);
  });

  test('removeAt with an out-of-range index is a no-op', () async {
    final c = _c(InMemoryBookmarkStore());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));
    await c.read(bookmarksProvider.notifier).add(1000);

    await c.read(bookmarksProvider.notifier).removeAt(9);

    expect(c.read(bookmarksProvider), hasLength(1));
  });

  test('insert undoes a removeAt, landing the bookmark back in its sorted slot', () async {
    final c = _c(InMemoryBookmarkStore());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));
    await c.read(bookmarksProvider.notifier).add(1000);
    await c.read(bookmarksProvider.notifier).add(5000);
    final removed = c.read(bookmarksProvider)[0]; // the 1000ms one
    await c.read(bookmarksProvider.notifier).removeAt(0);
    expect(c.read(bookmarksProvider), hasLength(1));

    await c.read(bookmarksProvider.notifier).insert(removed);

    expect(c.read(bookmarksProvider).map((b) => b.positionMs), [1000, 5000]);
  });

  test('switching video shows the new video bookmarks immediately', () {
    final store = InMemoryBookmarkStore();
    store.put('a.mkv', const [Bookmark(positionMs: 1, name: 'A', createdAtMs: 0)]);
    store.put('b.mkv', const [Bookmark(positionMs: 2, name: 'B', createdAtMs: 0)]);
    final c = _c(store);
    addTearDown(c.dispose);
    final videos = c.read(currentVideoProvider.notifier);

    videos.open(_session('a.mkv'));
    expect(c.read(bookmarksProvider).single.name, 'A');

    videos.open(_session('b.mkv'));
    expect(c.read(bookmarksProvider).single.name, 'B');
  });
}
