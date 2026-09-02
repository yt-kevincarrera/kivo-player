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
import 'package:kivo_player/ui/home/state/library_filter_state.dart';
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

  group('marking playlists for bulk delete', () {
    Future<ProviderContainer> twoPlaylists() async {
      final store = InMemoryPlaylistStore();
      final c = await _c(store, const []);
      await c.read(mediaIndexProvider.future);
      await c.read(playlistsProvider.notifier).create('Serie');
      await c.read(playlistsProvider.notifier).create('Curso');
      return c;
    }

    testWidgets('long-pressing a row marks it and brings up the selection bar',
        (tester) async {
      final c = await twoPlaylists();
      addTearDown(c.dispose);
      await _pump(tester, c);

      // Keyed rather than find.text('Borrar'): every row now carries its own
      // swipe-to-delete button reading the same word, hidden behind the row
      // until swiped — this checks the bulk-select BAR specifically.
      const bulkBorrar = Key('playlists-bulk-borrar');
      expect(find.byKey(bulkBorrar), findsNothing);

      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();

      expect(find.byKey(bulkBorrar), findsOneWidget);
      expect(find.textContaining('1'), findsWidgets);
    });

    testWidgets('while selecting, tapping a row toggles its mark instead of opening it',
        (tester) async {
      final c = await twoPlaylists();
      addTearDown(c.dispose);
      await _pump(tester, c);

      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistScreen), findsNothing);

      // A plain tap on the OTHER row, while selecting, marks it too — it must
      // NOT open the playlist screen.
      await tester.tap(find.text('Curso'));
      await tester.pumpAndSettle();

      expect(find.byType(PlaylistScreen), findsNothing);
      expect(find.textContaining('2'), findsWidgets);

      // Tapping the first row again un-marks it (down to 1).
      await tester.tap(find.text('Serie'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistScreen), findsNothing);
      expect(find.text('Borrar'), findsOneWidget);
    });

    testWidgets('unmarking the last selected row hides the selection bar again',
        (tester) async {
      final c = await twoPlaylists();
      addTearDown(c.dispose);
      await _pump(tester, c);

      const bulkBorrar = Key('playlists-bulk-borrar');
      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();
      expect(find.byKey(bulkBorrar), findsOneWidget);

      await tester.tap(find.text('Serie'));
      await tester.pumpAndSettle();

      // Keyed rather than find.text('Borrar'): once selecting ends, every
      // row's own (hidden, swiped-closed) Borrar button is back in the tree.
      expect(find.byKey(bulkBorrar), findsNothing);
    });

    testWidgets('the Nueva lista FAB is hidden while the selection bar is up',
        (tester) async {
      final c = await twoPlaylists();
      addTearDown(c.dispose);
      await _pump(tester, c);

      expect(find.text('Nueva lista'), findsOneWidget);

      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva lista'), findsNothing);
      expect(find.text('Borrar'), findsOneWidget);
    });

    testWidgets('Cancelar in the selection bar clears the marks without deleting',
        (tester) async {
      final store = InMemoryPlaylistStore();
      final c = await _c(store, const []);
      addTearDown(c.dispose);
      await c.read(mediaIndexProvider.future);
      await c.read(playlistsProvider.notifier).create('Serie');
      await c.read(playlistsProvider.notifier).create('Curso');
      await _pump(tester, c);

      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Keyed rather than find.text('Borrar') — see the marking test above.
      expect(find.byKey(const Key('playlists-bulk-borrar')), findsNothing);
      expect(find.text('Nueva lista'), findsOneWidget);
      expect(store.all().length, 2);
    });

    testWidgets(
        'Borrar asks to confirm naming how many lists, and deletes only on confirm',
        (tester) async {
      final store = InMemoryPlaylistStore();
      final c = await _c(store, const []);
      addTearDown(c.dispose);
      await c.read(mediaIndexProvider.future);
      await c.read(playlistsProvider.notifier).create('Serie');
      await c.read(playlistsProvider.notifier).create('Curso');
      await _pump(tester, c);

      const bulkBorrar = Key('playlists-bulk-borrar');
      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Curso'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(bulkBorrar));
      await tester.pumpAndSettle();

      // Names the count and reuses the "cannot be undone" register from
      // playlist_screen.dart's own delete confirm.
      expect(find.textContaining('2'), findsWidgets);
      expect(find.textContaining('no se puede deshacer'), findsOneWidget);

      // Cancelling the confirm (the dialog's own Cancelar, not the bar's)
      // leaves both playlists untouched and the selection still active.
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Cancelar')));
      await tester.pumpAndSettle();
      expect(store.all().length, 2);

      await tester.tap(find.byKey(bulkBorrar));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Borrar')));
      await tester.pumpAndSettle();

      expect(store.all(), isEmpty);
      // The selection bar is gone — nothing left to select. (No rows either:
      // an empty playlist list renders the empty state, not swipe buttons.)
      expect(find.byKey(bulkBorrar), findsNothing);
    });

    // Leaving the tab clears the marks; that is wired where the pager lives,
    // so its test is in library_screen_test.dart.
  });

  group('swipe actions on a row', () {
    testWidgets(
        'swiping a row left reveals Borrar, and tapping it deletes without a dialog',
        (tester) async {
      final store = InMemoryPlaylistStore();
      final c = await _c(store, const []);
      addTearDown(c.dispose);
      await c.read(mediaIndexProvider.future);
      final serie = await c.read(playlistsProvider.notifier).create('Serie');
      await _pump(tester, c);

      // The button is always mounted (just visually covered) behind a closed
      // row, so its presence isn't the useful signal here — being tappable
      // is; the swipe left is what should make it reachable.
      final swipeBorrar = Key('playlist-swipe-borrar-${serie.id}');

      await tester.drag(find.text('Serie'), const Offset(-200, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(swipeBorrar));
      await tester.pumpAndSettle();

      // The tap on the revealed button IS the confirmation (spec) — unlike
      // the bulk-delete bar's Borrar, there is no dialog after it.
      expect(find.byType(AlertDialog), findsNothing);
      expect(store.all(), isEmpty);
    });

    testWidgets('swiping a row right reveals Renombrar and opens the rename dialog',
        (tester) async {
      final store = InMemoryPlaylistStore();
      final c = await _c(store, const []);
      addTearDown(c.dispose);
      await c.read(mediaIndexProvider.future);
      final serie = await c.read(playlistsProvider.notifier).create('Serie');
      await _pump(tester, c);

      final swipeRenombrar = Key('playlist-swipe-renombrar-${serie.id}');

      await tester.drag(find.text('Serie'), const Offset(200, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(swipeRenombrar));
      await tester.pumpAndSettle();

      // Same dialog shape as playlist_screen.dart's own rename: title,
      // pre-filled TextField, Guardar actually renames.
      expect(find.text('Renombrar lista'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Temporada 2');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(store.all().single.name, 'Temporada 2');
    });

    testWidgets("opening one row's swipe actions closes another's", (tester) async {
      final store = InMemoryPlaylistStore();
      final c = await _c(store, const []);
      addTearDown(c.dispose);
      await c.read(mediaIndexProvider.future);
      final serie = await c.read(playlistsProvider.notifier).create('Serie');
      final curso = await c.read(playlistsProvider.notifier).create('Curso');
      await _pump(tester, c);

      final serieBorrar = Key('playlist-swipe-borrar-${serie.id}');
      final cursoBorrar = Key('playlist-swipe-borrar-${curso.id}');

      await tester.drag(find.text('Serie'), const Offset(-200, 0));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Curso'), const Offset(-200, 0));
      await tester.pumpAndSettle();

      // Serie's row auto-closed the moment Curso's opened. Its Borrar button
      // is still in the tree (just covered again), so tapping where it lives
      // now lands on the row's own foreground instead — which, per spec,
      // closes Curso's reveal rather than deleting anything. warnIfMissed is
      // off because this miss (on the covered button) is the point being
      // tested, not an accident.
      await tester.tap(find.byKey(serieBorrar), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(store.all().map((p) => p.name).toSet(), {'Serie', 'Curso'});

      // Curso's own Borrar is unaffected and still works on its own.
      await tester.drag(find.text('Curso'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(cursoBorrar));
      await tester.pumpAndSettle();

      expect(store.all().map((p) => p.name).toList(), ['Serie']);
    });

    testWidgets('swiping does nothing while rows are marked for bulk delete',
        (tester) async {
      final store = InMemoryPlaylistStore();
      final c = await _c(store, const []);
      addTearDown(c.dispose);
      await c.read(mediaIndexProvider.future);
      final serie = await c.read(playlistsProvider.notifier).create('Serie');
      await c.read(playlistsProvider.notifier).create('Curso');
      await _pump(tester, c);

      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playlists-bulk-borrar')), findsOneWidget);

      await tester.drag(find.text('Serie'), const Offset(-200, 0));
      await tester.pumpAndSettle();

      // No swipe button ever entered the tree — swiping is fully disabled
      // while marking is active, not merely hidden behind the row.
      expect(find.byKey(Key('playlist-swipe-borrar-${serie.id}')), findsNothing);
      // Nothing about the mark itself was disturbed by the failed drag.
      expect(find.byKey(const Key('playlists-bulk-borrar')), findsOneWidget);
      expect(store.all().length, 2);
    });
  });

  group('searching playlists', () {
    testWidgets(
        'Borrar in the selection bar only deletes lists a search query still shows',
        (tester) async {
      // Marking survives typing in the search box — the mark and the filter
      // are independent state — so a query narrowing the visible rows must
      // not let bulk delete reach a row it just hid.
      final store = InMemoryPlaylistStore();
      final c = await _c(store, const []);
      addTearDown(c.dispose);
      await c.read(mediaIndexProvider.future);
      await c.read(playlistsProvider.notifier).create('Serie');
      await c.read(playlistsProvider.notifier).create('Curso');
      await _pump(tester, c);

      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Curso'));
      await tester.pumpAndSettle();
      expect(c.read(playlistsSelectionProvider).length, 2);

      c.read(librarySearchActiveProvider.notifier).state = true;
      c.read(librarySearchQueryProvider.notifier).state = 'serie';
      await tester.pumpAndSettle();
      expect(find.text('Serie'), findsOneWidget);
      expect(find.text('Curso'), findsNothing);
      // The mark on the now-hidden Curso survives the query change.
      expect(c.read(playlistsSelectionProvider).length, 2);
      // …but the bar counts only what is on screen, so it agrees with the
      // delete it is about to offer.
      expect(find.text('1 lista seleccionada'), findsOneWidget);

      await tester.tap(find.byKey(const Key('playlists-bulk-borrar')));
      await tester.pumpAndSettle();
      // Names only the one still on screen, not both marked.
      expect(find.textContaining('¿Borrar 1 lista?'), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Borrar')));
      await tester.pumpAndSettle();

      expect(store.all().map((p) => p.name).toList(), ['Curso']);
    });

    testWidgets(
        'a query matching no list offers Borrar búsqueda, which clears it',
        (tester) async {
      final store = InMemoryPlaylistStore();
      final c = await _c(store, const []);
      addTearDown(c.dispose);
      await c.read(mediaIndexProvider.future);
      await c.read(playlistsProvider.notifier).create('Serie');
      await _pump(tester, c);

      c.read(librarySearchActiveProvider.notifier).state = true;
      c.read(librarySearchQueryProvider.notifier).state = 'zzz';
      await tester.pumpAndSettle();

      expect(find.textContaining('Ninguna lista coincide con "zzz"'),
          findsOneWidget);
      expect(find.text('Borrar búsqueda'), findsOneWidget);

      await tester.tap(find.text('Borrar búsqueda'));
      await tester.pumpAndSettle();

      // No owner was wired in (this widget is standalone here), so the
      // built-in fallback fires: both filter providers reset and the full
      // list is back.
      expect(c.read(librarySearchQueryProvider), isEmpty);
      expect(c.read(librarySearchActiveProvider), isFalse);
      expect(find.text('Serie'), findsOneWidget);
    });
  });
}
