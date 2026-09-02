import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../open/video_source.dart';
import 'bookmark.dart';
import 'bookmark_store.dart';

/// The open video's bookmarks, always sorted by position. The single writer
/// for the store's entry under the current video's key.
class BookmarksNotifier extends Notifier<List<Bookmark>> {
  BookmarkStore get _store => ref.read(bookmarkStoreProvider);

  @override
  List<Bookmark> build() {
    final session = ref.watch(currentVideoProvider);
    if (session == null) return const [];
    return _sorted(_store.forVideo(session.resumeKey));
  }

  List<Bookmark> _sorted(List<Bookmark> list) =>
      [...list]..sort((a, b) => a.positionMs.compareTo(b.positionMs));

  /// Saves the current position immediately, unnamed — asking for a name up
  /// front is what makes people never bookmark anything. Rename after, from
  /// the SnackBar or the sheet. Returns the created bookmark so a caller
  /// (the "Nombrar" SnackBar action) can find it again by identity.
  Future<Bookmark> add(int positionMs) async {
    final bookmark = Bookmark(
      positionMs: positionMs,
      name: '',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final key = ref.read(currentVideoProvider)?.resumeKey;
    if (key == null) return bookmark;
    // Synchronous, before the write — see the comment on _update in
    // playlist_controller.dart for why: the UI that triggered this expects
    // the very next build to already show the new bookmark.
    final next = _sorted([...state, bookmark]);
    state = next;
    await _store.put(key, next);
    return bookmark;
  }

  Future<void> rename(int index, String name) async {
    final key = ref.read(currentVideoProvider)?.resumeKey;
    if (key == null || index < 0 || index >= state.length) return;
    final next = [
      for (var i = 0; i < state.length; i++)
        i == index ? state[i].copyWith(name: name) : state[i],
    ];
    state = next;
    await _store.put(key, next);
  }

  Future<void> removeAt(int index) async {
    final key = ref.read(currentVideoProvider)?.resumeKey;
    if (key == null || index < 0 || index >= state.length) return;
    final next = [...state]..removeAt(index);
    state = next;
    await _store.put(key, next);
  }

  /// Undo for [removeAt]. The list is always kept sorted by position, so
  /// there is no "same index" to restore the way a playlist's ordered
  /// entries need — adding [bookmark] back and resorting lands it in exactly
  /// the slot it was removed from.
  Future<void> insert(Bookmark bookmark) async {
    final key = ref.read(currentVideoProvider)?.resumeKey;
    if (key == null) return;
    final next = _sorted([...state, bookmark]);
    state = next;
    await _store.put(key, next);
  }
}

final bookmarksProvider = NotifierProvider<BookmarksNotifier, List<Bookmark>>(
  BookmarksNotifier.new,
);
