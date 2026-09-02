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
    // .select, not the whole VideoSession: advanceTo (repeat-video) and
    // setShuffle now hand out a NEW session object for the SAME video, and
    // VideoSession has no ==. Watching the object itself would drop and
    // reload this video's bookmarks on every such change — losing whatever
    // was mid-write and flashing the list empty for a frame, for a video
    // that never actually changed.
    final key = ref.watch(currentVideoProvider.select((s) => s?.resumeKey));
    if (key == null) return const [];
    return _sorted(_store.forVideo(key));
  }

  List<Bookmark> _sorted(List<Bookmark> list) =>
      [...list]..sort((a, b) => a.positionMs.compareTo(b.positionMs));

  /// The video a mutation should write to, or null if it must write nothing.
  ///
  /// [key] is the video the caller captured when its interaction began. A
  /// caller that never crosses an async gap (add/rename invoked in the same
  /// frame as the tap that triggers them) can omit it, and whatever video is
  /// open right now is used — the pre-existing behavior for those call
  /// sites, unchanged. A caller whose interaction spans an async gap (a
  /// rename dialog's await, a delete's SnackBar staying up for a few
  /// seconds) must pass the key it captured when that interaction started;
  /// if the open video has changed since, this returns null.
  ///
  /// `state` only ever holds the CURRENT video's list (see [build]), so a
  /// mutator must never be allowed to write under a stale key: that would
  /// either corrupt another video's stored bookmarks or splice one video's
  /// bookmark into whatever the sheet is now showing for a different one.
  String? _targetKey(String? key) {
    final current = ref.read(currentVideoProvider)?.resumeKey;
    if (current == null) return null;
    if (key != null && key != current) return null;
    return current;
  }

  /// Saves the current position immediately, unnamed — asking for a name up
  /// front is what makes people never bookmark anything. Rename after, from
  /// the SnackBar or the sheet. Returns the created bookmark so a caller
  /// (the "Nombrar" SnackBar action) can find it again by identity. Returns
  /// it unsaved (not added to state, nothing written) if [key] is given and
  /// is no longer the open video.
  Future<Bookmark> add(int positionMs, {String? key}) async {
    final bookmark = Bookmark(
      positionMs: positionMs,
      name: '',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final target = _targetKey(key);
    if (target == null) return bookmark;
    // Synchronous, before the write — see the comment on _update in
    // playlist_controller.dart for why: the UI that triggered this expects
    // the very next build to already show the new bookmark.
    final next = _sorted([...state, bookmark]);
    state = next;
    await _store.put(target, next);
    return bookmark;
  }

  /// Returns false — writing nothing — when [index] is out of range, or
  /// when [key] is given and is no longer the open video.
  Future<bool> rename(int index, String name, {String? key}) async {
    final target = _targetKey(key);
    if (target == null || index < 0 || index >= state.length) return false;
    final next = [
      for (var i = 0; i < state.length; i++)
        i == index ? state[i].copyWith(name: name) : state[i],
    ];
    state = next;
    await _store.put(target, next);
    return true;
  }

  /// Returns false — writing nothing — when [index] is out of range, or
  /// when [key] is given and is no longer the open video.
  Future<bool> removeAt(int index, {String? key}) async {
    final target = _targetKey(key);
    if (target == null || index < 0 || index >= state.length) return false;
    final next = [...state]..removeAt(index);
    state = next;
    await _store.put(target, next);
    return true;
  }

  /// Undo for [removeAt]. The list is always kept sorted by position, so
  /// there is no "same index" to restore the way a playlist's ordered
  /// entries need — adding [bookmark] back and resorting lands it in exactly
  /// the slot it was removed from.
  ///
  /// Returns false — writing nothing, dropping the undo — when [key] is
  /// given and is no longer the open video. This is deliberate, not a
  /// fallback: if the delete's SnackBar outlives the video it was shown for,
  /// silently doing nothing is correct — the alternative (writing the
  /// removed bookmark into whatever video now happens to be open) is the
  /// exact corruption this key exists to prevent.
  Future<bool> insert(Bookmark bookmark, {String? key}) async {
    final target = _targetKey(key);
    if (target == null) return false;
    final next = _sorted([...state, bookmark]);
    state = next;
    await _store.put(target, next);
    return true;
  }
}

final bookmarksProvider = NotifierProvider<BookmarksNotifier, List<Bookmark>>(
  BookmarksNotifier.new,
);
