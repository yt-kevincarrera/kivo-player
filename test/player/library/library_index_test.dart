import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import '../../fakes/fakes.dart';

// Named to match the existing convention in media_index_refresh_test.dart —
// there is no shared FakeMediaPermission in test/fakes/fakes.dart, each test
// file defines its own trivial granted-access permission.
class _GrantedPerm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

VideoItem _v(String name, String folder) => VideoItem(
    id: name, uri: 'content://$name', name: name, folder: folder,
    durationMs: 1000, sizeBytes: 10, dateAddedMs: 0);

Future<ProviderContainer> _c(List<VideoItem> videos) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(videos)),
    mediaPermissionImplProvider.overrideWithValue(_GrantedPerm()),
  ]);
}

void main() {
  test('with nothing excluded the library is the whole index', () async {
    final c = await _c([_v('a.mkv', 'Series'), _v('b.mp4', 'WhatsApp')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    expect(c.read(libraryIndexProvider).value!.length, 2);
  });

  test('an excluded folder disappears from the library', () async {
    final c = await _c([_v('a.mkv', 'Series'), _v('b.mp4', 'WhatsApp')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final s = c.read(settingsProvider);
    await c.read(settingsProvider.notifier)
        .set(s.copyWith(excludedFolders: const ['WhatsApp']));

    final visible = c.read(libraryIndexProvider).value!;
    expect(visible.map((v) => v.folder), ['Series']);
    // The raw scan is untouched — nothing was deleted.
    expect(c.read(mediaIndexProvider).value!.length, 2);
  });

  test('an exclusion for a folder that no longer exists is harmless', () async {
    final c = await _c([_v('a.mkv', 'Series')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final s = c.read(settingsProvider);
    await c.read(settingsProvider.notifier)
        .set(s.copyWith(excludedFolders: const ['Ghost']));

    expect(c.read(libraryIndexProvider).value!.length, 1);
  });

  test('the loading and error states pass straight through', () async {
    final c = await _c([_v('a.mkv', 'Series')]);
    addTearDown(c.dispose);
    expect(c.read(libraryIndexProvider).isLoading, true);
  });
}
