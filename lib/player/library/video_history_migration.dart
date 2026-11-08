import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media/video_identity.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../bookmarks/bookmark_store.dart';
import '../resume/resume_service.dart';
import '../tracks/track_prefs_store.dart';
import 'played.dart';
import 'history_names.dart';

/// Migrates filename-only history against the full, unfiltered media index.
/// Copies are written before removing the old key. Existing new history wins;
/// unresolved or conflicting legacy data stays archived and exportable.
class VideoHistoryMigration {
  VideoHistoryMigration({
    required this.resume,
    required this.played,
    required this.bookmarks,
    required this.tracks,
    this.otherVideos,
    HistoryNames? names,
  }) : names = names ?? InMemoryHistoryNames();

  final ResumeService resume;
  final PlayedStore played;
  final BookmarkStore bookmarks;
  final TrackPrefsStore tracks;
  final HistoryNames names;
  final Iterable<({String name, String key})> Function()? otherVideos;

  Future<void> _pending = Future.value();

  Future<void> migrate(List<VideoItem> videos) {
    final next = _pending.then((_) => _migrate(videos));
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> _migrate(List<VideoItem> videos) async {
    final byName = <String, Set<String>>{};
    for (final v in [
      ...videos.map((v) => (name: v.name, key: v.key)),
      ...?otherVideos?.call(),
    ]) {
      (byName[v.name] ??= {}).add(v.key);
    }
    final positions = {for (final e in resume.entries()) e.key: e};
    final marks = bookmarks.all();
    final prefs = tracks.all();
    final keys = {
      ...positions.keys,
      ...played.keys(),
      ...marks.keys,
      ...prefs.keys,
      ...resume.completedKeys,
    };
    final knownNames = names.all();
    for (final entry in byName.entries) {
      for (final key in entry.value) {
        if (keys.contains(key) && knownNames[key] != entry.key) {
          await names.put(key, entry.key);
        }
      }
    }
    for (final name in keys) {
      if (isVideoIdentity(name) || name.startsWith('legacy:v1:')) continue;
      final candidates = byName[name];
      if (candidates == null) continue; // unavailable media is kept untouched
      final archive = legacyVideoIdentity(name);
      await names.put(archive, name);
      final target = candidates.length == 1 && !keys.contains(archive)
          ? candidates.single
          : archive;
      await names.put(target, name);
      final position = positions[name];
      if (position != null) {
        final to = positions.containsKey(target) ? archive : target;
        if (!positions.containsKey(to)) await resume.rename(name, to);
      }
      if (played.isPlayed(name)) {
        await played.markPlayed(target);
        await played.remove(name);
      }
      if (resume.completedKeys.contains(name)) {
        await resume.markCompleted(target);
        await resume.markUnfinished(name);
      }
      if (marks.containsKey(name)) {
        final merged = {...?marks[target], ...marks[name]!}.toList();
        await bookmarks.put(target, merged);
        await bookmarks.remove(name);
      }
      if (prefs.containsKey(name)) {
        final to = prefs.containsKey(target) ? archive : target;
        if (!prefs.containsKey(to)) {
          await tracks.put(to, prefs[name]!);
          await tracks.remove(name);
        }
      }
    }
  }

  /// A confirmed file move (vault restore). Merge bookmarks; newer resume
  /// positions and existing destination track preferences take precedence.
  Future<void> move(String from, String to) async {
    if (from == to) return;
    final label = names.all()[from];
    if (label != null) await names.put(to, label);
    final entries = {for (final e in resume.entries()) e.key: e};
    if ((entries[from]?.updatedAtMs ?? -1) > (entries[to]?.updatedAtMs ?? -1)) {
      await resume.rename(from, to);
    } else {
      await resume.clear(from);
    }
    if (resume.completedKeys.contains(from)) {
      await resume.markCompleted(to);
      await resume.markUnfinished(from);
    }
    if (played.isPlayed(from)) {
      await played.markPlayed(to);
      await played.remove(from);
    }
    final oldBookmarks = bookmarks.forVideo(from);
    if (oldBookmarks.isNotEmpty) {
      await bookmarks.put(
        to,
        {...bookmarks.forVideo(to), ...oldBookmarks}.toList(),
      );
      await bookmarks.remove(from);
    }
    final oldPrefs = tracks.forKey(from);
    if (oldPrefs != null && tracks.forKey(to) == null) {
      await tracks.rename(from, to);
    }
  }
}

// The composition root supplies persistent stores. Unit/widget tests can
// exercise the pure stores without booting an app-wide migration.
final videoHistoryMigrationProvider = Provider<VideoHistoryMigration?>(
  (ref) => null,
);
