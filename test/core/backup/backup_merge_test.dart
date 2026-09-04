import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/backup/backup_file.dart';
import 'package:kivo_player/core/backup/backup_merge.dart';
import 'package:kivo_player/player/bookmarks/bookmark.dart';
import 'package:kivo_player/player/playlists/playlist.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/vault/vault_entry.dart';

BackupFile _backup({
  Map<String, dynamic> settings = const {},
  Map<String, ResumeBackupEntry> resume = const {},
  Set<String> played = const {},
  Map<String, VideoTrackPrefs> trackPrefs = const {},
  List<Playlist> playlists = const [],
  Map<String, List<Bookmark>> bookmarks = const {},
  List<VaultEntry> vault = const [],
}) =>
    BackupFile(
      app: '1.0.0',
      createdAtMs: 0,
      settings: settings,
      resume: resume,
      played: played,
      trackPrefs: trackPrefs,
      playlists: playlists,
      bookmarks: bookmarks,
      vault: vault,
    );

const _emptyCurrent = CurrentBackupData(
  played: {},
  bookmarks: {},
  playlists: [],
  trackPrefs: {},
  resume: {},
  vault: [],
);

void main() {
  group('played: union', () {
    test('adds keys not already played', () {
      final plan = buildRestorePlan(
        backup: _backup(played: {'a', 'b'}),
        current: const CurrentBackupData(
            played: {'a'}, bookmarks: {}, playlists: [], trackPrefs: {}, resume: {}, vault: []),
      );
      expect(plan.playedToAdd, {'b'});
      expect(plan.playedCounts.added, 1);
      expect(plan.playedCounts.unchanged, 1);
    });
  });

  group('bookmarks: per-video union by value', () {
    const existing = Bookmark(positionMs: 100, name: 'a', createdAtMs: 1);
    const fresh = Bookmark(positionMs: 200, name: 'b', createdAtMs: 2);

    test('adds new bookmarks, keeps existing ones unchanged', () {
      final plan = buildRestorePlan(
        backup: _backup(bookmarks: {
          'v.mp4': [existing, fresh],
        }),
        current: const CurrentBackupData(
          played: {},
          bookmarks: {
            'v.mp4': [existing],
          },
          playlists: [],
          trackPrefs: {},
          resume: {},
          vault: [],
        ),
      );
      expect(plan.bookmarksCounts.added, 1);
      expect(plan.bookmarksCounts.unchanged, 1);
      expect(plan.bookmarksToWrite['v.mp4'], containsAll([existing, fresh]));
    });

    test('a video with nothing new is not written at all', () {
      final plan = buildRestorePlan(
        backup: _backup(bookmarks: {
          'v.mp4': [existing],
        }),
        current: const CurrentBackupData(
          played: {},
          bookmarks: {
            'v.mp4': [existing],
          },
          playlists: [],
          trackPrefs: {},
          resume: {},
          vault: [],
        ),
      );
      expect(plan.bookmarksToWrite, isEmpty);
      expect(plan.bookmarksCounts.unchanged, 1);
    });
  });

  group('playlists: by id, local wins', () {
    const p1 = Playlist(id: 'p1', name: 'A', createdAtMs: 1, entries: []);
    const p2 = Playlist(id: 'p2', name: 'B', createdAtMs: 2, entries: []);
    // Same id as p1 but different content — local must win, so this must be
    // ignored entirely (counted unchanged, never written).
    const p1Renamed = Playlist(id: 'p1', name: 'Renamed', createdAtMs: 1, entries: []);

    test('missing playlists are added; existing ones are left untouched', () {
      final plan = buildRestorePlan(
        backup: _backup(playlists: [p1Renamed, p2]),
        current: const CurrentBackupData(
            played: {}, bookmarks: {}, playlists: [p1], trackPrefs: {}, resume: {}, vault: []),
      );
      expect(plan.playlistsToAdd, [p2]);
      expect(plan.playlistsCounts.added, 1);
      expect(plan.playlistsCounts.unchanged, 1);
    });
  });

  group('trackPrefs: backup wins on conflict', () {
    const oldPrefs = VideoTrackPrefs(subtitleDelayMs: 100);
    const newPrefs = VideoTrackPrefs(subtitleDelayMs: 500, audioDelayMs: 20);

    test('new key is added', () {
      final plan = buildRestorePlan(
        backup: _backup(trackPrefs: {'v.mp4': newPrefs}),
        current: _emptyCurrent,
      );
      expect(plan.trackPrefsToWrite['v.mp4']!.toMap(), newPrefs.toMap());
      expect(plan.trackPrefsCounts.added, 1);
    });

    test('conflicting key is overwritten by the backup value', () {
      final plan = buildRestorePlan(
        backup: _backup(trackPrefs: {'v.mp4': newPrefs}),
        current: const CurrentBackupData(
          played: {},
          bookmarks: {},
          playlists: [],
          trackPrefs: {'v.mp4': oldPrefs},
          resume: {},
          vault: [],
        ),
      );
      expect(plan.trackPrefsToWrite['v.mp4']!.toMap(), newPrefs.toMap());
      expect(plan.trackPrefsCounts.updated, 1);
    });

    test('identical value on both sides counts as unchanged and is not written', () {
      final plan = buildRestorePlan(
        backup: _backup(trackPrefs: {'v.mp4': oldPrefs}),
        current: const CurrentBackupData(
          played: {},
          bookmarks: {},
          playlists: [],
          trackPrefs: {'v.mp4': oldPrefs},
          resume: {},
          vault: [],
        ),
      );
      expect(plan.trackPrefsToWrite, isEmpty);
      expect(plan.trackPrefsCounts.unchanged, 1);
    });
  });

  group('resume: newer updatedAtMs wins', () {
    test('backup entry is newer -> updated', () {
      final plan = buildRestorePlan(
        backup: _backup(resume: {'v.mp4': const ResumeBackupEntry(200, 5000)}),
        current: const CurrentBackupData(
          played: {},
          bookmarks: {},
          playlists: [],
          trackPrefs: {},
          resume: {'v.mp4': ResumeBackupEntry(50, 1000)},
          vault: [],
        ),
      );
      expect(plan.resumeToWrite['v.mp4'], const ResumeBackupEntry(200, 5000));
      expect(plan.resumeCounts.updated, 1);
    });

    test('current entry is newer or equal -> kept, not overwritten', () {
      final plan = buildRestorePlan(
        backup: _backup(resume: {'v.mp4': const ResumeBackupEntry(10, 1000)}),
        current: const CurrentBackupData(
          played: {},
          bookmarks: {},
          playlists: [],
          trackPrefs: {},
          resume: {'v.mp4': ResumeBackupEntry(999, 1000)},
          vault: [],
        ),
      );
      expect(plan.resumeToWrite, isEmpty);
      expect(plan.resumeCounts.unchanged, 1);
    });
  });

  group('settings: replaced wholesale', () {
    test('a non-empty settings section will replace', () {
      final plan =
          buildRestorePlan(backup: _backup(settings: {'accentColor': 1}), current: _emptyCurrent);
      expect(plan.settingsWillReplace, isTrue);
    });

    test('an empty settings section will not replace', () {
      final plan = buildRestorePlan(backup: _backup(), current: _emptyCurrent);
      expect(plan.settingsWillReplace, isFalse);
    });
  });

  group('vault: union by entry identity', () {
    const v1 = VaultEntry(
        id: 'id1', privatePath: '/a', displayName: 'a.mp4', originalRelativePath: '');
    const v2 = VaultEntry(
        id: 'id2', privatePath: '/b', displayName: 'b.mp4', originalRelativePath: '');

    test('new id is added, existing id is left alone', () {
      final plan = buildRestorePlan(
        backup: _backup(vault: [v1, v2]),
        current: const CurrentBackupData(
            played: {}, bookmarks: {}, playlists: [], trackPrefs: {}, resume: {}, vault: [v1]),
      );
      expect(plan.vaultToAdd.map((e) => e.id), ['id2']);
      expect(plan.vaultCounts.added, 1);
      expect(plan.vaultCounts.unchanged, 1);
    });
  });

  group('idempotence', () {
    test('restoring the same backup twice produces no further changes', () {
      final backup = _backup(
        settings: {'accentColor': 1},
        played: {'a', 'b'},
        resume: {'v.mp4': const ResumeBackupEntry(100, 500)},
        trackPrefs: {'v.mp4': const VideoTrackPrefs(subtitleDelayMs: 50)},
        playlists: const [Playlist(id: 'p1', name: 'A', createdAtMs: 1, entries: [])],
        bookmarks: const {
          'v.mp4': [Bookmark(positionMs: 10, name: '', createdAtMs: 1)],
        },
        vault: const [
          VaultEntry(id: 'id1', privatePath: '/a', displayName: 'a.mp4', originalRelativePath: ''),
        ],
      );

      final firstPlan = buildRestorePlan(backup: backup, current: _emptyCurrent);
      expect(firstPlan.hasChanges, isTrue);

      // Simulate what apply() would have produced, then plan the exact same
      // backup again against that resulting state.
      final afterFirstApply = CurrentBackupData(
        played: {...firstPlan.playedToAdd},
        bookmarks: firstPlan.bookmarksToWrite,
        playlists: firstPlan.playlistsToAdd,
        trackPrefs: firstPlan.trackPrefsToWrite,
        resume: firstPlan.resumeToWrite,
        vault: firstPlan.vaultToAdd,
      );

      final secondPlan = buildRestorePlan(backup: backup, current: afterFirstApply);
      expect(secondPlan.playedToAdd, isEmpty);
      expect(secondPlan.bookmarksToWrite, isEmpty);
      expect(secondPlan.playlistsToAdd, isEmpty);
      expect(secondPlan.trackPrefsToWrite, isEmpty);
      expect(secondPlan.resumeToWrite, isEmpty);
      expect(secondPlan.vaultToAdd, isEmpty);
      // Settings always "replace" when present — that is idempotent by
      // nature (replacing with the same value changes nothing observable).
      expect(secondPlan.settingsWillReplace, isTrue);
    });
  });

  group('describeRestorePlan', () {
    test('lists every non-zero section and the settings note', () {
      final plan = RestorePlan(
        backup: _backup(),
        playedCounts: const SectionCounts(added: 2),
        playedToAdd: const {'a', 'b'},
        bookmarksCounts: const SectionCounts(added: 40),
        bookmarksToWrite: const {},
        playlistsCounts: const SectionCounts(added: 3),
        playlistsToAdd: const [],
        trackPrefsCounts: const SectionCounts(),
        trackPrefsToWrite: const {},
        resumeCounts: const SectionCounts(added: 12),
        resumeToWrite: const {},
        vaultCounts: const SectionCounts(),
        vaultToAdd: const [],
        settingsWillReplace: true,
      );
      final text = describeRestorePlan(plan);
      expect(text, contains('3 listas'));
      expect(text, contains('40 marcadores'));
      expect(text, contains('12 posiciones'));
      expect(text, contains('Los ajustes se reemplazarán.'));
    });

    test('says nothing to add when the plan is empty', () {
      final plan = RestorePlan(
        backup: _backup(),
        playedCounts: const SectionCounts(),
        playedToAdd: const {},
        bookmarksCounts: const SectionCounts(),
        bookmarksToWrite: const {},
        playlistsCounts: const SectionCounts(),
        playlistsToAdd: const [],
        trackPrefsCounts: const SectionCounts(),
        trackPrefsToWrite: const {},
        resumeCounts: const SectionCounts(),
        resumeToWrite: const {},
        vaultCounts: const SectionCounts(),
        vaultToAdd: const [],
        settingsWillReplace: false,
      );
      expect(describeRestorePlan(plan), 'No hay nada nuevo que añadir.');
      expect(plan.hasChanges, isFalse);
    });
  });
}
