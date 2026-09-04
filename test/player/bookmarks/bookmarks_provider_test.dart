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

/// Wraps a [BookmarkStore] and counts calls to [forVideo], so a test can
/// assert the store was (or wasn't) re-read — [forVideo] is what a rebuild
/// of [BookmarksNotifier.build] triggers.
class _CountingBookmarkStore implements BookmarkStore {
  _CountingBookmarkStore(this._inner);
  final BookmarkStore _inner;
  int forVideoCalls = 0;

  @override
  List<Bookmark> forVideo(String key) {
    forVideoCalls++;
    return _inner.forVideo(key);
  }

  @override
  Future<void> put(String key, List<Bookmark> bookmarks) =>
      _inner.put(key, bookmarks);

  @override
  Future<void> remove(String key) => _inner.remove(key);

  @override
  Future<void> rename(String oldKey, String newKey) =>
      _inner.rename(oldKey, newKey);

  @override
  Map<String, List<Bookmark>> all() => _inner.all();
}

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

  // --- Regression coverage for the cross-video-write bug -------------------
  //
  // advanceTo (repeat-video) and setShuffle hand out a NEW VideoSession
  // object for the SAME video, and VideoSession has no ==. Before the fix,
  // build() watched the whole session object, so a same-video session
  // change reloaded the store and discarded in-memory state; and every
  // mutator re-read currentVideoProvider at write time, so an interaction
  // that spans an async gap (a rename dialog, a delete's SnackBar) could
  // write into whatever video happened to be open when it finally resolved.

  test('a new session object for the same video does not reload the store', () {
    final store = _CountingBookmarkStore(InMemoryBookmarkStore());
    final c = _c(store);
    addTearDown(c.dispose);
    final videos = c.read(currentVideoProvider.notifier);

    videos.open(_session('a.mkv'));
    c.read(bookmarksProvider); // subscribes; runs build() once
    final callsAfterOpen = store.forVideoCalls;
    expect(callsAfterOpen, greaterThan(0));

    // Same video, new session object — e.g. advanceTo under repeat-video
    // producing a fresh VideoSession for the file already playing.
    videos.advanceTo(_session('a.mkv'));

    expect(store.forVideoCalls, callsAfterOpen); // build() did not rerun
  });

  test(
      'a stale key drops the write instead of corrupting the now-open video '
      '(the exact "Deshacer" cross-video scenario)', () async {
    final store = InMemoryBookmarkStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final videos = c.read(currentVideoProvider.notifier);

    // Open A, add a bookmark, then delete it — capturing the key the way
    // the sheet does, at the moment the delete (and its SnackBar) started.
    videos.open(_session('a.mkv'));
    await c.read(bookmarksProvider.notifier).add(1000);
    final removed = c.read(bookmarksProvider).single;
    const capturedKey = 'a.mkv';
    final removedOk =
        await c.read(bookmarksProvider.notifier).removeAt(0, key: capturedKey);
    expect(removedOk, isTrue);
    expect(c.read(bookmarksProvider), isEmpty);

    // A ends, autoplay advances, B opens — underneath the still-showing
    // SnackBar.
    videos.open(_session('b.mkv'));
    expect(c.read(bookmarksProvider), isEmpty);

    // The user taps "Deshacer" late, using the key captured when the delete
    // began (A's), not whatever is open now (B's).
    final applied =
        await c.read(bookmarksProvider.notifier).insert(removed, key: capturedKey);

    // Chosen behavior: the undo is dropped entirely rather than restored
    // anywhere. B must never receive A's bookmark — and since the user is no
    // longer looking at A either, silently writing it back into A's storage
    // out from under them is no better, so nothing is written at all.
    expect(applied, isFalse);
    expect(c.read(bookmarksProvider), isEmpty); // B's list: untouched
    expect(store.forVideo('a.mkv'), isEmpty); // A's list: not restored
    expect(store.forVideo('b.mkv'), isEmpty);
  });

  test('rename with a stale key does not touch the new video list', () async {
    final store = InMemoryBookmarkStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final videos = c.read(currentVideoProvider.notifier);

    videos.open(_session('a.mkv'));
    const capturedKey = 'a.mkv'; // captured when a rename dialog opened on A

    // The video changes underneath the still-open dialog.
    videos.open(_session('b.mkv'));
    await c.read(bookmarksProvider.notifier).add(2000); // B has one bookmark

    final applied = await c
        .read(bookmarksProvider.notifier)
        .rename(0, 'Oops, wrong video', key: capturedKey);

    expect(applied, isFalse);
    expect(c.read(bookmarksProvider).single.name, ''); // B's bookmark: untouched
    expect(store.forVideo('b.mkv').single.name, '');
    expect(store.forVideo('a.mkv'), isEmpty);
  });

  test('callers that omit key keep writing to whatever video is open now',
      () async {
    // Same-frame callers (more_menu.dart's "Marcar aquí" / "Nombrar", which
    // never cross an async gap) still work with no key argument at all.
    final store = InMemoryBookmarkStore();
    final c = _c(store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));

    final bookmark = await c.read(bookmarksProvider.notifier).add(1000);
    final ok = await c
        .read(bookmarksProvider.notifier)
        .rename(0, 'Nombrado', key: null);

    expect(ok, isTrue);
    expect(bookmark.positionMs, 1000);
    expect(c.read(bookmarksProvider).single.name, 'Nombrado');
  });
}
