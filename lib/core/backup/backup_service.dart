import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/app_installer_provider.dart';
import '../../player/bookmarks/bookmark_store.dart';
import '../../player/library/played.dart';
import '../../player/open/video_source.dart'; // resumeServiceProvider
import '../../player/playlists/playlist_store.dart';
import '../../player/tracks/track_prefs_store.dart';
import '../../vault/vault_providers.dart';
import '../settings/kivo_settings.dart';
import '../settings/settings_provider.dart';
import 'backup_file.dart';
import 'backup_merge.dart';

/// Builds, plans, and applies a Kivo backup against the live stores.
///
/// NOTE — a known, deliberate gap: [BookmarkStore] and [TrackPrefsStore]
/// have no way to enumerate every key they hold (no `entries()`/`all()`),
/// only per-key reads (`forVideo`/`forKey`) and per-key writes (`put`). That
/// means [exportJson] cannot discover which videos have bookmarks or track
/// prefs, so those two sections are always exported empty — this is a real
/// limitation, not a bug, and needs one of those two stores to grow an
/// enumeration method to fix. [plan]/[apply], by contrast, work correctly
/// for both sections on a backup that already names its keys (e.g. one made
/// by a future Kivo that can enumerate them, or restored on a second
/// device): plan() looks up each key the backup mentions individually, and
/// apply() writes each one back through the store's existing `put`.
class BackupService {
  final Ref _ref;
  BackupService(this._ref);

  Future<String> exportJson() async {
    final settings = _ref.read(settingsProvider);
    final resumeEntries = _ref.read(resumeServiceProvider).entries();
    final playedKeys = _ref.read(playedStoreProvider).keys();
    final playlists = _ref.read(playlistStoreProvider).all();
    final vaultEntries = _ref.read(vaultStoreProvider).readAll();
    final appVersion = await _ref.read(appInstallerProvider).appVersion();

    final backup = BackupFile(
      app: appVersion,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      settings: settings.toMap(),
      resume: {
        for (final e in resumeEntries)
          e.key: ResumeBackupEntry(e.seconds, e.updatedAtMs),
      },
      played: playedKeys,
      // See the class doc: no enumeration method on these two stores yet.
      trackPrefs: const {},
      playlists: playlists,
      bookmarks: const {},
      vault: vaultEntries,
    );
    return backup.toJson();
  }

  /// Parses [json] and compares it against what is on the device now.
  /// Throws [BackupFormatException] or [BackupTooNewException] — never a raw
  /// parse exception — when [json] isn't a readable Kivo backup.
  Future<RestorePlan> plan(String json) async {
    final backup = BackupFile.fromJson(json);

    final bookmarkStore = _ref.read(bookmarkStoreProvider);
    final trackPrefsStore = _ref.read(trackPrefsStoreProvider);
    final resumeEntries = _ref.read(resumeServiceProvider).entries();

    final current = CurrentBackupData(
      played: _ref.read(playedStoreProvider).keys(),
      bookmarks: {
        for (final key in backup.bookmarks.keys)
          key: bookmarkStore.forVideo(key),
      },
      playlists: _ref.read(playlistStoreProvider).all(),
      trackPrefs: {
        for (final key in backup.trackPrefs.keys)
          if (trackPrefsStore.forKey(key) != null)
            key: trackPrefsStore.forKey(key)!,
      },
      resume: {
        for (final e in resumeEntries)
          e.key: ResumeBackupEntry(e.seconds, e.updatedAtMs),
      },
      vault: _ref.read(vaultStoreProvider).readAll(),
    );

    return buildRestorePlan(backup: backup, current: current);
  }

  /// Writes [plan]'s merged data back through each store's own public
  /// methods — nothing here reaches into a box directly.
  Future<void> apply(RestorePlan plan) async {
    if (plan.settingsWillReplace) {
      await _ref
          .read(settingsProvider.notifier)
          .set(KivoSettings.fromMap(plan.backup.settings));
    }

    final playedStore = _ref.read(playedStoreProvider);
    for (final key in plan.playedToAdd) {
      await playedStore.markPlayed(key);
    }

    // Restoring a saved position is not "the video just finished" — record()
    // applies live thresholds (min-seconds, finished-tail) meant for that
    // event. Passing Duration.zero as the total skips the finished check
    // (see ResumeService.record), and updatedAtMs is passed through as
    // nowMs so the restored entry keeps its original timestamp rather than
    // being stamped with "now". The one live threshold that still applies
    // is resumeMinSeconds — a short saved position can be dropped if the
    // device's current setting is stricter than whatever it was when the
    // backup was made; ResumeService has no raw "put" to bypass that, and
    // this service doesn't own that file.
    final resumeService = _ref.read(resumeServiceProvider);
    for (final entry in plan.resumeToWrite.entries) {
      await resumeService.record(
        entry.key,
        Duration(seconds: entry.value.seconds),
        Duration.zero,
        entry.value.updatedAtMs,
      );
    }

    final playlistStore = _ref.read(playlistStoreProvider);
    for (final p in plan.playlistsToAdd) {
      await playlistStore.put(p);
    }

    final bookmarkStore = _ref.read(bookmarkStoreProvider);
    for (final entry in plan.bookmarksToWrite.entries) {
      await bookmarkStore.put(entry.key, entry.value);
    }

    final trackPrefsStore = _ref.read(trackPrefsStoreProvider);
    for (final entry in plan.trackPrefsToWrite.entries) {
      await trackPrefsStore.put(entry.key, entry.value);
    }

    if (plan.vaultToAdd.isNotEmpty) {
      final vaultStore = _ref.read(vaultStoreProvider);
      final merged = [...vaultStore.readAll(), ...plan.vaultToAdd];
      await vaultStore.writeAll(merged);
    }
  }
}

final backupServiceProvider =
    Provider<BackupService>((ref) => BackupService(ref));
