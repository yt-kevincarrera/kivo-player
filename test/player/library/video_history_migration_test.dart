import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/media/video_identity.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/bookmarks/bookmark.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/library/video_history_migration.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import '../../fakes/fakes.dart';

const a = VideoItem(
  id: '1',
  uri: 'content://media/1',
  name: '01.mp4',
  folder: 'A',
  path: 'A/',
  durationMs: 100000,
  sizeBytes: 1,
  dateAddedMs: 0,
);
const b = VideoItem(
  id: '2',
  uri: 'content://media/2',
  name: '01.mp4',
  folder: 'B',
  path: 'B/',
  durationMs: 100000,
  sizeBytes: 1,
  dateAddedMs: 0,
);
const mark = Bookmark(positionMs: 1000, name: 'Intro', createdAtMs: 1);

void main() {
  late InMemoryResumeStore positions;
  late ResumeService resume;
  late InMemoryPlayedStore played;
  late InMemoryBookmarkStore bookmarks;
  late InMemoryTrackPrefsStore tracks;
  late VideoHistoryMigration migration;

  setUp(() {
    positions = InMemoryResumeStore();
    resume = ResumeService(positions);
    played = InMemoryPlayedStore();
    bookmarks = InMemoryBookmarkStore();
    tracks = InMemoryTrackPrefsStore();
    migration = VideoHistoryMigration(
      resume: resume,
      played: played,
      bookmarks: bookmarks,
      tracks: tracks,
    );
  });

  Future<void> seed() async {
    await positions.put('01.mp4', 42, 123);
    await played.markPlayed('01.mp4');
    await bookmarks.put('01.mp4', [mark]);
    await tracks.put('01.mp4', const VideoTrackPrefs(audioDelayMs: 200));
  }

  test(
    'different locations never share history or track preferences',
    () async {
      expect(a.key, isNot(b.key));
      await positions.put(a.key, 30, 1);
      await bookmarks.put(a.key, [mark]);
      await played.markPlayed(a.key);
      expect(resume.positionFor(b.key), isNull);
      expect(bookmarks.forVideo(b.key), isEmpty);
      expect(played.isPlayed(b.key), isFalse);
    },
  );

  test(
    'unique legacy history migrates without changing its timestamp',
    () async {
      await seed();
      await migration.migrate([a]);
      await migration.migrate([a]);
      expect(resume.positionFor(a.key), const Duration(seconds: 42));
      expect(resume.entries().single.updatedAtMs, 123);
      expect(resume.positionFor('01.mp4'), isNull);
      expect(played.keys(), {a.key});
      expect(bookmarks.forVideo(a.key), [mark]);
      expect(tracks.forKey(a.key)!.audioDelayMs, 200);
    },
  );

  test(
    'ambiguous legacy data stays archived after one duplicate disappears',
    () async {
      await seed();
      await migration.migrate([a, b]);
      await migration.migrate([a]);
      final archive = legacyVideoIdentity('01.mp4');
      expect(resume.positionFor(archive), const Duration(seconds: 42));
      expect(bookmarks.forVideo(archive), [mark]);
      expect(resume.positionFor(a.key), isNull);
      expect(resume.positionFor(b.key), isNull);
      expect(played.keys(), {archive});
    },
  );

  test(
    'new history wins and conflicting old positions remain exportable',
    () async {
      await seed();
      await positions.put(a.key, 80, 500);
      await migration.migrate([a]);
      expect(resume.positionFor(a.key), const Duration(seconds: 80));
      expect(
        resume.positionFor(legacyVideoIdentity(a.name)),
        const Duration(seconds: 42),
      );
      await resume.clear(a.key);
      await migration.migrate([a]);
      expect(resume.positionFor(a.key), isNull);
    },
  );

  test('unavailable videos keep their old data until a later scan', () async {
    await seed();
    await migration.migrate([]);
    expect(resume.positionFor('01.mp4'), const Duration(seconds: 42));
    await migration.migrate([a]);
    expect(resume.positionFor(a.key), const Duration(seconds: 42));
  });

  test('vault names participate in legacy ambiguity checks', () async {
    await seed();
    migration = VideoHistoryMigration(
      resume: resume,
      played: played,
      bookmarks: bookmarks,
      tracks: tracks,
      otherVideos: () => [(name: b.name, key: b.key)],
    );
    await migration.migrate([a]);
    expect(resume.positionFor(a.key), isNull);
    expect(resume.positionFor(legacyVideoIdentity(a.name)), isNotNull);
  });

  test('long Unicode paths produce bounded keys for Hive and subtitles', () {
    final key = videoIdentity(
      '/${List.filled(100, 'película').join('/')}',
      '01.mp4',
    );
    expect(key.length, lessThan(255));
    expect(key, isNot(contains('/')));
  });

  test(
    'completion requires the end threshold and clears on a new watch',
    () async {
      await resume.record(
        a.key,
        const Duration(seconds: 1),
        const Duration(seconds: 100),
        1,
      );
      expect(resume.completedKeys, isEmpty);
      await resume.record(
        a.key,
        const Duration(seconds: 97),
        const Duration(seconds: 100),
        2,
      );
      expect(resume.completedKeys, {a.key});
      expect(resume.positionFor(a.key), isNull);
      await resume.record(
        a.key,
        const Duration(seconds: 10),
        const Duration(seconds: 100),
        3,
      );
      expect(resume.completedKeys, isEmpty);
      expect(resume.positionFor(a.key), const Duration(seconds: 10));
    },
  );
}
