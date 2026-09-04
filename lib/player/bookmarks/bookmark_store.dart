import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'bookmark.dart';

/// Bookmarks keyed by video file name — the same resumeKey/displayName key
/// the resume and played stores use, so a bookmark stays attached to a video
/// exactly as long as the app can still tell which file it is.
abstract class BookmarkStore {
  List<Bookmark> forVideo(String key);
  Future<void> put(String key, List<Bookmark> bookmarks);
  Future<void> remove(String key);
  Future<void> rename(String oldKey, String newKey);

  /// Every video that has at least one bookmark, keyed by video. Only
  /// [BackupService] needs this — everything else works one video at a time
  /// via [forVideo], which is why this was missing for a while.
  Map<String, List<Bookmark>> all();
}

class HiveBookmarkStore implements BookmarkStore {
  HiveBookmarkStore(this.box);
  final Box box;

  @override
  List<Bookmark> forVideo(String key) {
    final raw = box.get(key);
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(Bookmark.fromMap).toList();
  }

  @override
  Future<void> put(String key, List<Bookmark> bookmarks) =>
      box.put(key, bookmarks.map((b) => b.toMap()).toList());

  @override
  Future<void> remove(String key) => box.delete(key);

  @override
  Future<void> rename(String oldKey, String newKey) async {
    final existing = forVideo(oldKey);
    if (existing.isEmpty) return;
    await box.put(newKey, existing.map((b) => b.toMap()).toList());
    await box.delete(oldKey);
  }

  @override
  Map<String, List<Bookmark>> all() {
    final out = <String, List<Bookmark>>{};
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! List) continue; // tolerate a corrupt/foreign record
      out[key.toString()] = raw.whereType<Map>().map(Bookmark.fromMap).toList();
    }
    return out;
  }
}

/// Session-only store: a valid fallback and what the tests use.
class InMemoryBookmarkStore implements BookmarkStore {
  final Map<String, List<Bookmark>> _data = {};

  @override
  List<Bookmark> forVideo(String key) => List.of(_data[key] ?? const []);

  @override
  Future<void> put(String key, List<Bookmark> bookmarks) async =>
      _data[key] = List.of(bookmarks);

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> rename(String oldKey, String newKey) async {
    final existing = _data.remove(oldKey);
    if (existing != null) _data[newKey] = existing;
  }

  @override
  Map<String, List<Bookmark>> all() =>
      {for (final e in _data.entries) e.key: List.of(e.value)};
}

// Deliberately throws rather than defaulting to an in-memory store: a video's
// bookmarks silently failing to persist (every test still green) is exactly
// the bug this app has already been bitten by once — see playedStoreProvider.
final bookmarkStoreProvider = Provider<BookmarkStore>((ref) {
  throw UnimplementedError('bookmarkStoreProvider must be overridden');
});
