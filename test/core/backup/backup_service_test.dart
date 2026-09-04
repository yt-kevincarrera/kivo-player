import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/backup/backup_file.dart';
import 'package:kivo_player/core/backup/backup_service.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart'; // resumeServiceProvider
import 'package:kivo_player/player/playlists/playlist.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/vault/vault_entry.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_store.dart';

import '../../fakes/fakes.dart';

class _Stores {
  final InMemoryPlayedStore played = InMemoryPlayedStore();
  final InMemoryPlaylistStore playlists = InMemoryPlaylistStore();
  final InMemoryBookmarkStore bookmarks = InMemoryBookmarkStore();
  final InMemoryTrackPrefsStore trackPrefs = InMemoryTrackPrefsStore();
  final InMemoryVaultStore vault = InMemoryVaultStore();
  final InMemoryResumeStore resumeStore = InMemoryResumeStore();
  late final ResumeService resumeService = ResumeService(resumeStore);
}

Future<(ProviderContainer, _Stores)> _container() async {
  final stores = _Stores();
  final settingsService = await SettingsService.load(InMemorySettingsStore());
  final container = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(settingsService),
    resumeServiceProvider.overrideWithValue(stores.resumeService),
    playedStoreProvider.overrideWithValue(stores.played),
    playlistStoreProvider.overrideWithValue(stores.playlists),
    bookmarkStoreProvider.overrideWithValue(stores.bookmarks),
    trackPrefsStoreProvider.overrideWithValue(stores.trackPrefs),
    vaultStoreProvider.overrideWithValue(stores.vault),
    appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.14.2')),
  ]);
  return (container, stores);
}

void main() {
  group('exportJson', () {
    test('carries settings, resume, played, playlists and vault', () async {
      final (container, stores) = await _container();
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).set(
          container.read(settingsProvider).copyWith(accentColor: 0xFF5B9BE8));
      await stores.resumeService.record(
          'ep1.mp4', const Duration(seconds: 90), const Duration(minutes: 40), 1000);
      await stores.played.markPlayed('ep2.mp4');
      await stores.playlists.put(const Playlist(
          id: 'p1', name: 'Serie', createdAtMs: 1, entries: []));
      await stores.vault.writeAll(const [
        VaultEntry(
            id: 'v1', privatePath: '/vault/v1.mp4', displayName: 'v1.mp4', originalRelativePath: '')
      ]);

      final json = await container.read(backupServiceProvider).exportJson();
      final decoded = BackupFile.fromJson(json);

      expect(decoded.settings['accentColor'], 0xFF5B9BE8);
      expect(decoded.resume['ep1.mp4']!.seconds, 90);
      expect(decoded.played, contains('ep2.mp4'));
      expect(decoded.playlists.single.id, 'p1');
      expect(decoded.vault.single.id, 'v1');
      expect(decoded.app, '1.14.2');
    });

    test('carries trackPrefs and bookmarks, keyed by video', () async {
      final (container, stores) = await _container();
      addTearDown(container.dispose);

      await stores.trackPrefs
          .put('ep1.mp4', const VideoTrackPrefs(subtitleDelayMs: 300));
      await stores.trackPrefs
          .put('ep2.mp4', const VideoTrackPrefs(audioDelayMs: -80));
      await stores.bookmarks.put('ep1.mp4', const [
        Bookmark(positionMs: 10, name: 'a', createdAtMs: 1),
        Bookmark(positionMs: 20, name: 'b', createdAtMs: 2),
      ]);

      final json = await container.read(backupServiceProvider).exportJson();
      final decoded = BackupFile.fromJson(json);

      expect(decoded.trackPrefs.keys, containsAll(['ep1.mp4', 'ep2.mp4']));
      expect(decoded.trackPrefs['ep1.mp4']!.subtitleDelayMs, 300);
      expect(decoded.trackPrefs['ep2.mp4']!.audioDelayMs, -80);
      expect(decoded.bookmarks['ep1.mp4']!.map((b) => b.name), ['a', 'b']);
    });
  });

  group('export -> plan -> apply round trip', () {
    test('lands every exportable section on a fresh target, then is idempotent',
        () async {
      final (source, sourceStores) = await _container();
      addTearDown(source.dispose);
      final (target, _) = await _container();
      addTearDown(target.dispose);

      await source.read(settingsProvider.notifier).set(
          source.read(settingsProvider).copyWith(accentColor: 0xFF57C08A));
      await sourceStores.resumeService.record(
          'ep1.mp4', const Duration(seconds: 45), const Duration(minutes: 40), 2000);
      await sourceStores.played.markPlayed('ep2.mp4');
      await sourceStores.playlists
          .put(const Playlist(id: 'p1', name: 'Serie', createdAtMs: 1, entries: []));
      await sourceStores.vault.writeAll(const [
        VaultEntry(
            id: 'v1', privatePath: '/vault/v1.mp4', displayName: 'v1.mp4', originalRelativePath: '')
      ]);

      final json = await source.read(backupServiceProvider).exportJson();

      final plan = await target.read(backupServiceProvider).plan(json);
      expect(plan.hasChanges, isTrue);
      await target.read(backupServiceProvider).apply(plan);

      expect(target.read(settingsProvider).accentColor, 0xFF57C08A);
      expect(target.read(resumeServiceProvider).positionFor('ep1.mp4'),
          const Duration(seconds: 45));
      expect(target.read(playedStoreProvider).isPlayed('ep2.mp4'), isTrue);
      expect(target.read(playlistStoreProvider).all().single.id, 'p1');
      expect(target.read(vaultStoreProvider).readAll().single.id, 'v1');

      // Restoring the exact same backup again changes nothing further.
      final secondPlan = await target.read(backupServiceProvider).plan(json);
      expect(secondPlan.playedToAdd, isEmpty);
      expect(secondPlan.playlistsToAdd, isEmpty);
      expect(secondPlan.vaultToAdd, isEmpty);
      expect(secondPlan.resumeToWrite, isEmpty);
    });

    test('reproduces bookmarks and trackPrefs exactly, and applying twice is idempotent',
        () async {
      final (source, sourceStores) = await _container();
      addTearDown(source.dispose);
      final (target, targetStores) = await _container();
      addTearDown(target.dispose);

      await sourceStores.trackPrefs.put(
          'ep1.mp4', const VideoTrackPrefs(subtitleDelayMs: 250, audioDelayMs: -10));
      await sourceStores.bookmarks.put('ep1.mp4', const [
        Bookmark(positionMs: 500, name: 'intro', createdAtMs: 1),
        Bookmark(positionMs: 9000, name: '', createdAtMs: 2),
      ]);

      final json = await source.read(backupServiceProvider).exportJson();

      final plan = await target.read(backupServiceProvider).plan(json);
      expect(plan.trackPrefsCounts.added, 1);
      expect(plan.bookmarksCounts.added, 2);
      await target.read(backupServiceProvider).apply(plan);

      expect(targetStores.trackPrefs.forKey('ep1.mp4')!.subtitleDelayMs, 250);
      expect(targetStores.trackPrefs.forKey('ep1.mp4')!.audioDelayMs, -10);
      expect(targetStores.bookmarks.forVideo('ep1.mp4').map((b) => b.name),
          ['intro', '']);

      // Applying the exact same export again changes nothing further.
      final secondPlan = await target.read(backupServiceProvider).plan(json);
      expect(secondPlan.trackPrefsToWrite, isEmpty);
      expect(secondPlan.bookmarksToWrite, isEmpty);
      expect(secondPlan.trackPrefsCounts.unchanged, 1);
      expect(secondPlan.bookmarksCounts.unchanged, 2);
      await target.read(backupServiceProvider).apply(secondPlan);

      expect(targetStores.trackPrefs.forKey('ep1.mp4')!.subtitleDelayMs, 250);
      expect(targetStores.bookmarks.forVideo('ep1.mp4').map((b) => b.name),
          ['intro', '']);
    });

    test('a restore never removes anything already on the target', () async {
      final (target, targetStores) = await _container();
      addTearDown(target.dispose);
      await targetStores.played.markPlayed('local-only.mp4');
      await targetStores.playlists
          .put(const Playlist(id: 'local', name: 'Local', createdAtMs: 1, entries: []));

      final (source, _) = await _container();
      addTearDown(source.dispose);
      await source.read(settingsProvider.notifier).set(
          source.read(settingsProvider).copyWith(accentColor: 0xFFE86B6B));
      final json = await source.read(backupServiceProvider).exportJson();

      final plan = await target.read(backupServiceProvider).plan(json);
      await target.read(backupServiceProvider).apply(plan);

      expect(target.read(playedStoreProvider).isPlayed('local-only.mp4'), isTrue);
      expect(
          target.read(playlistStoreProvider).all().map((p) => p.id), contains('local'));
    });
  });

  group('trackPrefs and bookmarks restore from a hand-made backup', () {
    test('a backup naming specific keys restores them via the store\'s '
        'existing put method, independent of exportJson', () async {
      final (target, targetStores) = await _container();
      addTearDown(target.dispose);

      const handMade = BackupFile(
        app: '1.0.0',
        createdAtMs: 0,
        settings: {},
        resume: {},
        played: {},
        trackPrefs: {
          'ep1.mp4': VideoTrackPrefs(subtitleDelayMs: 250, audioDelayMs: -10),
        },
        playlists: [],
        bookmarks: {
          'ep1.mp4': [Bookmark(positionMs: 500, name: 'intro', createdAtMs: 1)],
        },
        vault: [],
      );

      final plan = await target.read(backupServiceProvider).plan(handMade.toJson());
      expect(plan.trackPrefsCounts.added, 1);
      expect(plan.bookmarksCounts.added, 1);
      await target.read(backupServiceProvider).apply(plan);

      expect(targetStores.trackPrefs.forKey('ep1.mp4')!.subtitleDelayMs, 250);
      expect(targetStores.bookmarks.forVideo('ep1.mp4').single.name, 'intro');

      // Idempotent: planning the same file again sees no new work.
      final secondPlan = await target.read(backupServiceProvider).plan(handMade.toJson());
      expect(secondPlan.trackPrefsToWrite, isEmpty);
      expect(secondPlan.bookmarksToWrite, isEmpty);
    });
  });

  group('plan errors', () {
    test('a newer-format backup throws BackupTooNewException, not a raw parse error',
        () async {
      final (target, _) = await _container();
      addTearDown(target.dispose);
      final future = target
          .read(backupServiceProvider)
          .plan('{"kivo": ${kBackupFormatVersion + 1}}');
      await expectLater(future, throwsA(isA<BackupTooNewException>()));
    });

    test('garbage input throws BackupFormatException', () async {
      final (target, _) = await _container();
      addTearDown(target.dispose);
      final future = target.read(backupServiceProvider).plan('not json at all');
      await expectLater(future, throwsA(isA<BackupFormatException>()));
    });
  });
}
