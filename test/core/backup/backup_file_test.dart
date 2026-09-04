import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/backup/backup_file.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/player/bookmarks/bookmark.dart';
import 'package:kivo_player/player/playlists/playlist.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/vault/vault_entry.dart';

BackupFile _sample() => BackupFile(
      app: '1.14.2',
      createdAtMs: 1000,
      settings: KivoSettings.defaults()
          .copyWith(accentColor: 0xFF5B9BE8, libraryColumns: 2)
          .toMap(),
      resume: const {
        'ep1.mp4': ResumeBackupEntry(120, 5000),
        'ep2.mp4': ResumeBackupEntry(30, 6000),
      },
      played: const {'ep1.mp4', 'ep3.mp4'},
      trackPrefs: const {
        'ep1.mp4': VideoTrackPrefs(
            subtitleDelayMs: 200, audioDelayMs: -50, subtitlePath: '/subs/a.srt'),
      },
      playlists: const [
        Playlist(id: 'p1', name: 'Serie', createdAtMs: 500, entries: [
          PlaylistEntry(mediaId: 'm1', displayName: 'ep1.mp4'),
        ]),
      ],
      bookmarks: const {
        'ep1.mp4': [Bookmark(positionMs: 1000, name: 'intro', createdAtMs: 900)],
      },
      vault: const [
        VaultEntry(
          id: 'v1',
          privatePath: '/vault/v1.mp4',
          displayName: 'v1.mp4',
          originalRelativePath: 'Movies/',
          durationMs: 1000,
          sizeBytes: 2000,
          dateAddedMs: 3000,
          width: 100,
          height: 200,
        ),
      ],
    );

void main() {
  group('round-trip', () {
    test('toJson -> fromJson reproduces every section', () {
      final original = _sample();
      final decoded = BackupFile.fromJson(original.toJson());

      expect(decoded.app, original.app);
      expect(decoded.createdAtMs, original.createdAtMs);
      expect(decoded.settings['accentColor'], 0xFF5B9BE8);
      expect(decoded.settings['libraryColumns'], 2);
      expect(decoded.resume['ep1.mp4'], const ResumeBackupEntry(120, 5000));
      expect(decoded.resume['ep2.mp4'], const ResumeBackupEntry(30, 6000));
      expect(decoded.played, {'ep1.mp4', 'ep3.mp4'});
      expect(decoded.trackPrefs['ep1.mp4']!.subtitleDelayMs, 200);
      expect(decoded.trackPrefs['ep1.mp4']!.audioDelayMs, -50);
      expect(decoded.trackPrefs['ep1.mp4']!.subtitlePath, '/subs/a.srt');
      expect(decoded.playlists.single.id, 'p1');
      expect(decoded.playlists.single.entries.single.mediaId, 'm1');
      expect(decoded.bookmarks['ep1.mp4']!.single.name, 'intro');
      expect(decoded.vault.single.id, 'v1');
      expect(decoded.vault.single.privatePath, '/vault/v1.mp4');
    });

    test('toMap stamps the current format version', () {
      expect(_sample().toMap()['kivo'], kBackupFormatVersion);
    });
  });

  group('tolerance', () {
    test('missing sections default to empty rather than throwing', () {
      final decoded = BackupFile.fromJson(jsonEncode({'kivo': 1, 'app': '1.0.0'}));
      expect(decoded.settings, isEmpty);
      expect(decoded.resume, isEmpty);
      expect(decoded.played, isEmpty);
      expect(decoded.trackPrefs, isEmpty);
      expect(decoded.playlists, isEmpty);
      expect(decoded.bookmarks, isEmpty);
      expect(decoded.vault, isEmpty);
    });

    test('unknown top-level keys are ignored', () {
      final decoded = BackupFile.fromJson(jsonEncode({
        'kivo': 1,
        'app': '1.0.0',
        'somethingFromTheFuture': {'x': 1},
      }));
      expect(decoded.app, '1.0.0');
    });

    test('a missing kivo field is tolerated as version 1', () {
      final decoded = BackupFile.fromJson(jsonEncode({'app': '1.0.0'}));
      expect(decoded.app, '1.0.0');
    });

    test('malformed entries inside a section are skipped, not fatal', () {
      final decoded = BackupFile.fromJson(jsonEncode({
        'kivo': 1,
        'resume': {'ep1.mp4': 'not a map'},
        'playlists': [
          'not a map',
          {'id': 'p1', 'name': 'ok', 'created': 1, 'entries': []},
        ],
      }));
      expect(decoded.resume, isEmpty);
      expect(decoded.playlists, hasLength(1));
      expect(decoded.playlists.single.id, 'p1');
    });
  });

  group('version rejection', () {
    test('kivo above the current format version throws BackupTooNewException', () {
      final json = jsonEncode({'kivo': kBackupFormatVersion + 1, 'app': '9.0.0'});
      expect(() => BackupFile.fromJson(json),
          throwsA(isA<BackupTooNewException>()));
    });

    test('BackupTooNewException has a Spanish, user-facing message', () {
      final json = jsonEncode({'kivo': kBackupFormatVersion + 1});
      try {
        BackupFile.fromJson(json);
        fail('expected BackupTooNewException');
      } on BackupTooNewException catch (e) {
        expect(e.toString(), contains('más nueva de Kivo'));
      }
    });
  });

  group('malformed input', () {
    test('invalid JSON throws BackupFormatException', () {
      expect(() => BackupFile.fromJson('{not json'),
          throwsA(isA<BackupFormatException>()));
    });

    test('valid JSON that is not an object throws BackupFormatException', () {
      expect(() => BackupFile.fromJson('[1, 2, 3]'),
          throwsA(isA<BackupFormatException>()));
    });
  });
}
