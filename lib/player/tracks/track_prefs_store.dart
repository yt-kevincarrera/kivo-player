import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// What one video remembers about its tracks: how far subtitle and audio
/// timing were nudged, and which subtitle file the user loaded by hand.
///
/// These live together because they are one thing to the user — "the track
/// setup for this video" — and because they must be migrated and cleared
/// together when the file is renamed or deleted.
class VideoTrackPrefs {
  const VideoTrackPrefs({
    this.subtitleDelayMs = 0,
    this.audioDelayMs = 0,
    this.subtitlePath,
  });

  final int subtitleDelayMs;

  /// Offsets a badly muxed file's audio against its video. Per-video, not
  /// global: the cause is the file, not the output device.
  final int audioDelayMs;

  /// An app-owned copy, never the raw file-picker path — those go stale.
  final String? subtitlePath;

  bool get isEmpty =>
      subtitleDelayMs == 0 && audioDelayMs == 0 && subtitlePath == null;

  static const _unset = Object();

  VideoTrackPrefs copyWith({
    int? subtitleDelayMs,
    int? audioDelayMs,
    Object? subtitlePath = _unset,
  }) =>
      VideoTrackPrefs(
        subtitleDelayMs: subtitleDelayMs ?? this.subtitleDelayMs,
        audioDelayMs: audioDelayMs ?? this.audioDelayMs,
        subtitlePath: identical(subtitlePath, _unset)
            ? this.subtitlePath
            : subtitlePath as String?,
      );

  // 'd' is the subtitle offset's original key, kept so records written before
  // audio delay existed still load. 'a' is the newcomer.
  Map<String, dynamic> toMap() =>
      {'d': subtitleDelayMs, 'a': audioDelayMs, 'p': subtitlePath};

  factory VideoTrackPrefs.fromMap(Map m) => VideoTrackPrefs(
        subtitleDelayMs: (m['d'] as num?)?.toInt() ?? 0,
        audioDelayMs: (m['a'] as num?)?.toInt() ?? 0,
        subtitlePath: m['p'] as String?,
      );
}

abstract class TrackPrefsStore {
  VideoTrackPrefs? forKey(String key);
  Future<void> put(String key, VideoTrackPrefs prefs);
  Future<void> remove(String key);
  Future<void> rename(String oldKey, String newKey);
}

class HiveTrackPrefsStore implements TrackPrefsStore {
  HiveTrackPrefsStore(this.box);
  final Box box;

  @override
  VideoTrackPrefs? forKey(String key) {
    final raw = box.get(key);
    return raw is Map ? VideoTrackPrefs.fromMap(raw) : null;
  }

  @override
  Future<void> put(String key, VideoTrackPrefs prefs) =>
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
class InMemoryTrackPrefsStore implements TrackPrefsStore {
  final Map<String, VideoTrackPrefs> _data = {};

  @override
  VideoTrackPrefs? forKey(String key) => _data[key];

  @override
  Future<void> put(String key, VideoTrackPrefs prefs) async {
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

final trackPrefsStoreProvider = Provider<TrackPrefsStore>(
    (ref) => InMemoryTrackPrefsStore());
