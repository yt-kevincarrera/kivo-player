import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kivo_player/core/media/video_identity.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/library/history_names.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/library/video_history_migration.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/resume/resume_store.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';

import '../../fakes/fakes.dart';

const _a = VideoItem(
  id: '1',
  uri: 'content://media/1',
  name: '01.mp4',
  folder: 'A',
  durationMs: 100000,
  sizeBytes: 1,
  dateAddedMs: 0,
);
const _b = VideoItem(
  id: '2',
  uri: 'content://media/2',
  name: '01.mp4',
  folder: 'B',
  durationMs: 100000,
  sizeBytes: 1,
  dateAddedMs: 0,
);

class _LimitedAccess implements MediaPermission {
  @override
  Future<MediaAccess> request() async => MediaAccess.limited;
  @override
  Future<MediaAccess> status() async => MediaAccess.limited;
}

class _FailOnceBookmarks extends InMemoryBookmarkStore {
  bool fail = true;
  @override
  Future<void> put(String key, List<Bookmark> bookmarks) async {
    if (isVideoIdentity(key) && fail) {
      fail = false;
      throw StateError('temporary write failure');
    }
    await super.put(key, bookmarks);
  }
}

void main() {
  test(
    'ambiguous history and completion survive closing and reopening Hive',
    () async {
      final dir = Directory.systemTemp.createTempSync('kivo_history_');
      Hive.init(dir.path);
      addTearDown(() async {
        await Hive.close();
        await dir.delete(recursive: true);
      });

      Future<VideoHistoryMigration> open() async => VideoHistoryMigration(
        resume: ResumeService(
          HiveResumeStore(await Hive.openBox('resume')),
          completedStore: HivePlayedStore(await Hive.openBox('completed')),
        ),
        played: HivePlayedStore(await Hive.openBox('played')),
        bookmarks: HiveBookmarkStore(await Hive.openBox('bookmarks')),
        tracks: HiveTrackPrefsStore(await Hive.openBox('tracks')),
        names: HiveHistoryNames(await Hive.openBox('names')),
      );
      var history = await open();
      await history.resume.record(
        '01.mp4',
        const Duration(seconds: 20),
        const Duration(seconds: 100),
        123,
      );
      await history.bookmarks.put('01.mp4', const [
        Bookmark(positionMs: 1000, name: 'Intro', createdAtMs: 1),
      ]);
      await history.resume.markCompleted(_b.key);
      await history.migrate([_a, _b]);
      await Hive.close();

      history = await open();
      await history.migrate([_a]);
      final archive = legacyVideoIdentity('01.mp4');
      expect(history.resume.positionFor(_a.key), isNull);
      expect(history.resume.positionFor(archive), const Duration(seconds: 20));
      expect(history.resume.entries().single.updatedAtMs, 123);
      expect(history.bookmarks.forVideo(archive).single.name, 'Intro');
      expect(history.names.all()[archive], '01.mp4');
      expect(history.resume.completedKeys, {_b.key});
    },
  );

  test(
    'retry after a partial migration keeps new progress and finishes bookmarks',
    () async {
      final resume = ResumeService(InMemoryResumeStore());
      final marks = _FailOnceBookmarks();
      final history = VideoHistoryMigration(
        resume: resume,
        played: InMemoryPlayedStore(),
        bookmarks: marks,
        tracks: InMemoryTrackPrefsStore(),
      );
      await resume.record(
        '01.mp4',
        const Duration(seconds: 20),
        const Duration(seconds: 100),
        1,
      );
      await marks.put('01.mp4', const [
        Bookmark(positionMs: 1000, name: 'Intro', createdAtMs: 1),
      ]);
      await expectLater(history.migrate([_a]), throwsStateError);
      await resume.record(
        _a.key,
        const Duration(seconds: 70),
        const Duration(seconds: 100),
        2,
      );
      await history.migrate([_a]);
      expect(resume.positionFor(_a.key), const Duration(seconds: 70));
      expect(marks.forVideo(_a.key).single.name, 'Intro');
      expect(marks.forVideo('01.mp4'), isEmpty);
    },
  );

  test(
    'a partial media grant never guesses legacy identity from its subset',
    () async {
      final resume = ResumeService(InMemoryResumeStore());
      await resume.record(
        '01.mp4',
        const Duration(seconds: 20),
        const Duration(seconds: 100),
        1,
      );
      final history = VideoHistoryMigration(
        resume: resume,
        played: InMemoryPlayedStore(),
        bookmarks: InMemoryBookmarkStore(),
        tracks: InMemoryTrackPrefsStore(),
      );
      final container = ProviderContainer(
        overrides: [
          mediaPermissionImplProvider.overrideWithValue(_LimitedAccess()),
          mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([_a])),
          videoHistoryMigrationProvider.overrideWithValue(history),
        ],
      );
      addTearDown(container.dispose);
      await container.read(mediaIndexProvider.future);
      expect(resume.positionFor(_a.key), isNull);
      expect(resume.positionFor('01.mp4'), const Duration(seconds: 20));
    },
  );
}
