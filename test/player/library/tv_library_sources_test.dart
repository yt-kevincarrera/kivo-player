import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/interfaces/storage_browser.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/storage_browser_provider.dart';
import 'package:kivo_player/platform/television_provider.dart';
import 'package:kivo_player/player/library/continue_watching.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import '../../fakes/fakes.dart';

class _Permission implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() => status();
}

class _Usb implements StorageBrowser {
  _Usb(this.items, {this.fail = false});
  final List<VideoItem> items;
  final bool fail;
  int scans = 0;
  @override
  Future<List<VideoItem>> scanRemovable() async {
    scans++;
    if (fail) throw StateError('Drive disconnected');
    return items;
  }

  @override
  Future<List<StorageVolume>> volumes() async => [];
  @override
  Future<List<StorageEntry>> list(String path) async => [];
  @override
  Future<Uint8List?> thumbnail(String path) async => null;
}

VideoItem _video(String id, String path, {int duration = 0}) => VideoItem(
  id: id,
  uri: id.startsWith('tv:') ? Uri.file(path).toString() : 'content://media/$id',
  name: path.split('/').last,
  folder: 'USB',
  durationMs: duration,
  sizeBytes: 10,
  dateAddedMs: 0,
  filePath: path,
);

void main() {
  test(
    'TV merges unindexed USB videos without duplicating MediaStore identities',
    () async {
      final indexed = _video('12', '/storage/usb/film.mkv', duration: 600000);
      final usb = _Usb([
        _video('tv:film', '/storage/usb/film.mkv'),
        _video('tv:clip', '/storage/usb/clip.avi'),
      ]);
      final c = ProviderContainer(
        overrides: [
          isTelevisionProvider.overrideWithValue(true),
          mediaPermissionImplProvider.overrideWithValue(_Permission()),
          mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([indexed])),
          storageBrowserProvider.overrideWithValue(usb),
        ],
      );
      addTearDown(c.dispose);
      final videos = await c.read(mediaIndexProvider.future);
      expect(videos.map((v) => v.name), ['film.mkv', 'clip.avi']);
      expect(videos.first.durationMs, 600000);
      expect(videos.first.key, usb.items.first.key);
    },
  );

  test(
    'a disconnected USB does not hide indexed videos; phones never scan USB directly',
    () async {
      for (final television in [true, false]) {
        final indexed = _video(
          '12',
          '/storage/emulated/0/film.mp4',
          duration: 600000,
        );
        final usb = _Usb([], fail: true);
        final c = ProviderContainer(
          overrides: [
            isTelevisionProvider.overrideWithValue(television),
            mediaPermissionImplProvider.overrideWithValue(_Permission()),
            mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([indexed])),
            storageBrowserProvider.overrideWithValue(usb),
          ],
        );
        addTearDown(c.dispose);
        expect(await c.read(mediaIndexProvider.future), [indexed]);
        expect(usb.scans, television ? 1 : 0);
      }
    },
  );

  test(
    'TV keeps a USB resume entry while its duration is not yet indexed',
    () async {
      final video = _video('tv:film', '/storage/usb/film.mkv');
      final resume = ResumeService(InMemoryResumeStore());
      await resume.record(
        video.key,
        const Duration(seconds: 60),
        const Duration(minutes: 10),
        1,
      );
      final c = ProviderContainer(
        overrides: [
          isTelevisionProvider.overrideWithValue(true),
          libraryIndexProvider.overrideWithValue(AsyncData([video])),
          resumeServiceProvider.overrideWithValue(resume),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(continueWatchingProvider).single.seconds, 60);
    },
  );
}
