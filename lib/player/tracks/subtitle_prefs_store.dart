import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// What one video remembers about its subtitles: how far its timing was
/// nudged, and which file the user loaded by hand.
///
/// These two live together because they are the same thing to the user — "the
/// subtitle setup for this video" — and because they must be migrated and
/// cleared together when the file is renamed or deleted.
class VideoSubtitlePrefs {
  const VideoSubtitlePrefs({this.delayMs = 0, this.subtitlePath});

  final int delayMs;

  /// An app-owned copy, never the raw file-picker path — those go stale.
  final String? subtitlePath;

  bool get isEmpty => delayMs == 0 && subtitlePath == null;

  static const _unset = Object();

  VideoSubtitlePrefs copyWith({int? delayMs, Object? subtitlePath = _unset}) =>
      VideoSubtitlePrefs(
        delayMs: delayMs ?? this.delayMs,
        subtitlePath: identical(subtitlePath, _unset)
            ? this.subtitlePath
            : subtitlePath as String?,
      );

  Map<String, dynamic> toMap() => {'d': delayMs, 'p': subtitlePath};

  factory VideoSubtitlePrefs.fromMap(Map m) => VideoSubtitlePrefs(
        delayMs: (m['d'] as num?)?.toInt() ?? 0,
        subtitlePath: m['p'] as String?,
      );
}

abstract class SubtitlePrefsStore {
  VideoSubtitlePrefs? forKey(String key);
  Future<void> put(String key, VideoSubtitlePrefs prefs);
  Future<void> remove(String key);
  Future<void> rename(String oldKey, String newKey);
}

class HiveSubtitlePrefsStore implements SubtitlePrefsStore {
  HiveSubtitlePrefsStore(this.box);
  final Box box;

  @override
  VideoSubtitlePrefs? forKey(String key) {
    final raw = box.get(key);
    return raw is Map ? VideoSubtitlePrefs.fromMap(raw) : null;
  }

  @override
  Future<void> put(String key, VideoSubtitlePrefs prefs) =>
      // An all-defaults record is indistinguishable from having none, so don't
      // let resetting a delay leave a row behind forever.
      prefs.isEmpty ? box.delete(key) : box.put(key, prefs.toMap());

  @override
  Future<void> remove(String key) => box.delete(key);

  @override
  Future<void> rename(String oldKey, String newKey) async {
    final existing = forKey(oldKey);
    if (existing == null) return;
    await put(newKey, existing);
    await box.delete(oldKey);
  }
}

/// Session-only store: a valid fallback and what the tests use.
class InMemorySubtitlePrefsStore implements SubtitlePrefsStore {
  final Map<String, VideoSubtitlePrefs> _data = {};

  @override
  VideoSubtitlePrefs? forKey(String key) => _data[key];

  @override
  Future<void> put(String key, VideoSubtitlePrefs prefs) async {
    if (prefs.isEmpty) {
      _data.remove(key);
    } else {
      _data[key] = prefs;
    }
  }

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> rename(String oldKey, String newKey) async {
    final existing = _data[oldKey];
    if (existing == null) return;
    _data[newKey] = existing;
    _data.remove(oldKey);
  }
}

final subtitlePrefsStoreProvider = Provider<SubtitlePrefsStore>(
    (ref) => InMemorySubtitlePrefsStore());
