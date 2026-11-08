import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/app_installer_provider.dart';
import '../../player/bookmarks/bookmark_store.dart';
import '../../player/library/played.dart';
import '../../player/library/media_index.dart';
import '../../player/library/continue_watching.dart';
import '../../player/library/video_history_migration.dart';
import '../../player/library/history_names.dart';
import '../../player/library/media_permission.dart';
import '../../platform/interfaces/media_permission.dart';
import '../../player/resume/resume_store.dart';
import '../../player/open/video_source.dart'; // resumeServiceProvider
import '../../player/playlists/playlist_store.dart';
import '../../player/tracks/track_prefs_store.dart';
import '../../vault/vault_providers.dart';
import '../settings/kivo_settings.dart';
import '../settings/settings_provider.dart';
import 'backup_file.dart';
import 'backup_merge.dart';

/// Builds, plans, and applies a Kivo backup against the live stores.
class BackupService {
  final Ref _ref;
  BackupService(this._ref);

  Future<String> exportJson() async {
    final settings = _ref.read(settingsProvider);
    final resumeEntries = _ref.read(resumeServiceProvider).entries();
    final playedKeys = _ref.read(playedStoreProvider).keys();
    final playlists = _ref.read(playlistStoreProvider).all();
    final vaultEntries = _ref.read(vaultStoreProvider).readAll();
    final trackPrefs = _ref.read(trackPrefsStoreProvider).all();
    final bookmarks = _ref.read(bookmarkStoreProvider).all();
    final completed = _ref.read(resumeServiceProvider).completedKeys;
    final historyKeys = {
      ...resumeEntries.map((e) => e.key),
      ...playedKeys,
      ...completed,
      ...bookmarks.keys,
      ...trackPrefs.keys,
      ...vaultEntries.map((v) => v.key),
    };
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
      completed: completed,
      historyNames: {
        for (final e in _ref.read(historyNamesProvider).all().entries)
          if (historyKeys.contains(e.key)) e.key: e.value,
      },
      trackPrefs: trackPrefs,
      playlists: playlists,
      bookmarks: bookmarks,
      vault: vaultEntries,
    );
    return backup.toJson();
  }

  /// Parses [json] and compares it against what is on the device now.
  /// Throws [BackupFormatException] or [BackupTooNewException] — never a raw
  /// parse exception — when [json] isn't a readable Kivo backup.
  Future<RestorePlan> plan(String json) async {
    final backup = BackupFile.fromJson(json);
    try {
      KivoSettings.fromMap(backup.settings);
    } on TypeError {
      throw const BackupFormatException('invalid settings');
    }
    final resumeEntries = _ref.read(resumeServiceProvider).entries();

    final current = CurrentBackupData(
      played: _ref.read(playedStoreProvider).keys(),
      completed: _ref.read(resumeServiceProvider).completedKeys,
      bookmarks: _ref.read(bookmarkStoreProvider).all(),
      playlists: _ref.read(playlistStoreProvider).all(),
      trackPrefs: _ref.read(trackPrefsStoreProvider).all(),
      resume: {
        for (final e in resumeEntries)
          e.key: ResumeBackupEntry(e.seconds, e.updatedAtMs),
      },
      vault: _ref.read(vaultStoreProvider).readAll(),
    );

    return buildRestorePlan(backup: backup, current: current);
  }

  /// Writes [requested]'s merged data back through each store's own public
  /// methods — nothing here reaches into a box directly.
  Future<void> apply(RestorePlan requested) async {
    // Playback or an earlier failed restore may have changed the stores while
    // the confirmation dialog was open. Re-merge before writing.
    final plan = await this.plan(requested.backup.toJson());
    final names = _ref.read(historyNamesProvider);
    final currentNames = names.all();
    for (final entry in plan.backup.historyNames.entries) {
      if (!currentNames.containsKey(entry.key)) {
        await names.put(entry.key, entry.value);
      }
    }
    if (plan.settingsWillReplace) {
      await _ref
          .read(settingsProvider.notifier)
          .set(KivoSettings.fromMap(plan.backup.settings));
    }

    final playedStore = _ref.read(playedStoreProvider);
    for (final key in plan.playedToAdd) {
      await playedStore.markPlayed(key);
    }

    // A backup is an exact saved position, not a live playback event.
    final resumeService = _ref.read(resumeServiceProvider);
    for (final entry in plan.resumeToWrite.entries) {
      await resumeService.restore(
        ResumeEntry(entry.key, entry.value.seconds, entry.value.updatedAtMs),
      );
    }
    for (final key in plan.completedToAdd) {
      await resumeService.markCompleted(key);
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
    final index = _ref.exists(mediaIndexProvider)
        ? _ref.read(mediaIndexProvider).valueOrNull
        : null;
    if (index != null &&
        _ref.read(mediaPermissionProvider).valueOrNull == MediaAccess.granted) {
      await _ref.read(videoHistoryMigrationProvider)?.migrate(index);
    }
    _ref.invalidate(playedKeysProvider);
    _ref.invalidate(continueWatchingProvider);
  }
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref),
);
