import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/playlists/playlist.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/ui/home/playlists/add_to_playlist_sheet.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

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
  await pumpLocalized(
    tester,
    Consumer(
      builder: (ctx, ref, _) => Scaffold(
        body: Builder(
          builder: (b) => TextButton(
            onPressed: () => showAddToPlaylistSheet(b, ref, const [_v]),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    container: c,
  );
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
    await tester.tap(find.text(_l10n.playlistNewListLabel));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Curso');
    await tester.tap(find.text(_l10n.commonCreate));
    await tester.pumpAndSettle();

    expect(store.all().single.name, 'Curso');
    expect(store.all().single.entries.single.displayName, 'ep1.mkv');
  });

  testWidgets('a blank name is refused rather than creating «»', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store);
    addTearDown(c.dispose);

    await _open(tester, c);
    await tester.tap(find.text(_l10n.playlistNewListLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.commonCreate));
    await tester.pumpAndSettle();

    expect(store.all(), isEmpty);
  });

  testWidgets('with no playlists yet it says so and still offers to create one',
      (tester) async {
    final c = await _c(InMemoryPlaylistStore());
    addTearDown(c.dispose);

    await _open(tester, c);
    expect(find.textContaining('Todavía no tienes listas'), findsOneWidget);
    expect(find.text(_l10n.playlistNewListLabel), findsOneWidget);
  });

  testWidgets('the sheet closes before the writes, not after', (tester) async {
    // The sheet is dismissible. If it only popped once create+addVideos had
    // finished, a user who swiped it away mid-write would have that pop land
    // on the screen underneath and get sent back a level.
    final slow = _SlowStore(InMemoryPlaylistStore());
    final c = await _c(slow);
    addTearDown(c.dispose);

    await _open(tester, c);
    await tester.tap(find.text(_l10n.playlistNewListLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Curso');
    await tester.tap(find.text(_l10n.commonCreate));
    await tester.pumpAndSettle();

    // The write is still in flight, and the sheet is already gone.
    expect(find.text(_l10n.playlistAddToListLabel), findsNothing);
    expect(find.text('open'), findsOneWidget);

    slow.gate.complete();
    await tester.pumpAndSettle();
    expect(slow.all().single.name, 'Curso');
    expect(find.text('open'), findsOneWidget);
  });
}

/// Holds every write open until [gate] is completed, so a test can look at
/// the screen while a create is still in flight.
class _SlowStore implements PlaylistStore {
  _SlowStore(this._inner);
  final PlaylistStore _inner;
  final gate = Completer<void>();

  @override
  List<Playlist> all() => _inner.all();

  @override
  Future<void> put(Playlist playlist) async {
    await gate.future;
    await _inner.put(playlist);
  }

  @override
  Future<void> remove(String id) => _inner.remove(id);
}
