import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/ui/home/playlists/add_to_playlist_sheet.dart';
import '../../fakes/fakes.dart';

const _v = VideoItem(
  id: '1',
  uri: 'content://1',
  name: 'ep1.mkv',
  folder: 'Series',
  durationMs: 1000,
  sizeBytes: 10,
  dateAddedMs: 0,
);

Future<ProviderContainer> _c(PlaylistStore store) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  var tick = 0;
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    playlistStoreProvider.overrideWithValue(store),
    playlistClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
  ]);
}

Future<void> _open(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Consumer(
        builder: (ctx, ref, _) => Scaffold(
          body: Builder(
            builder: (b) => TextButton(
              onPressed: () => showAddToPlaylistSheet(b, ref, const [_v]),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the playlists and adds to the one tapped', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store);
    addTearDown(c.dispose);
    await c.read(playlistsProvider.notifier).create('Serie');

    await _open(tester, c);
    expect(find.text('Serie'), findsOneWidget);

    await tester.tap(find.text('Serie'));
    await tester.pumpAndSettle();

    expect(store.all().single.entries.single.displayName, 'ep1.mkv');
  });

  testWidgets('creating a new list from the sheet adds the videos to it',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store);
    addTearDown(c.dispose);

    await _open(tester, c);
    await tester.tap(find.text('Nueva lista'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Curso');
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();

    expect(store.all().single.name, 'Curso');
    expect(store.all().single.entries.single.displayName, 'ep1.mkv');
  });

  testWidgets('a blank name is refused rather than creating «»', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store);
    addTearDown(c.dispose);

    await _open(tester, c);
    await tester.tap(find.text('Nueva lista'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();

    expect(store.all(), isEmpty);
  });

  testWidgets('with no playlists yet it says so and still offers to create one',
      (tester) async {
    final c = await _c(InMemoryPlaylistStore());
    addTearDown(c.dispose);

    await _open(tester, c);
    expect(find.textContaining('Todavía no tienes listas'), findsOneWidget);
    expect(find.text('Nueva lista'), findsOneWidget);
  });
}
