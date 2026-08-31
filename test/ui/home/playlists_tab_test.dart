// test/ui/home/playlists_tab_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/ui/home/playlists/playlist_screen.dart';
import 'package:kivo_player/ui/home/playlists/playlists_tab.dart';
import '../../fakes/fakes.dart';

VideoItem _v(String id, String name) => VideoItem(
      id: id,
      uri: 'content://$id',
      name: name,
      folder: 'Series',
      durationMs: 1000,
      sizeBytes: 10,
      dateAddedMs: 0,
    );

// Named to match the convention already used in
// test/player/playlists/playlist_playback_test.dart — there is no shared
// FakeMediaPermission in test/fakes/fakes.dart.
class _GrantedPerm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

// Copy the mediaIndexerProvider / mediaPermissionImplProvider overrides from an
// existing test in test/player/library/ — do not invent fake names.
Future<ProviderContainer> _c(PlaylistStore store, List<VideoItem> index) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  var tick = 0;
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(index)),
    mediaPermissionImplProvider.overrideWithValue(_GrantedPerm()),
    playlistStoreProvider.overrideWithValue(store),
    playlistClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
  ]);
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: PlaylistsTab())),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with no playlists it explains what they are for', (tester) async {
    final c = await _c(InMemoryPlaylistStore(), const []);
    addTearDown(c.dispose);
    await _pump(tester, c);

    expect(find.textContaining('Todavía no tienes listas'), findsOneWidget);
  });

  testWidgets('shows each playlist with how many videos it holds',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    await _pump(tester, c);

    expect(find.text('Serie'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets);
  });

  testWidgets('a playlist whose videos are all missing still appears',
      (tester) async {
    // The list is the user's; an empty device does not delete it.
    final store = InMemoryPlaylistStore();
    final c = await _c(store, const []);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await _pump(tester, c);
    expect(find.text('Serie'), findsOneWidget);
  });

  testWidgets('tapping a playlist row opens its screen', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await _pump(tester, c);
    expect(find.byType(PlaylistScreen), findsNothing);

    await tester.tap(find.text('Serie'));
    await tester.pumpAndSettle();

    final screen = tester.widget<PlaylistScreen>(find.byType(PlaylistScreen));
    expect(screen.playlistId, p.id);
  });
}
