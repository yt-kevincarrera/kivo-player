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

/// Mounts PlaylistsTab inside a 3-page PageView shaped like
/// library_screen.dart's real sub-tab pager (Todo=0, Carpetas=1, Listas=2),
/// so the tab-leave-clears-selection behavior — which watches the ambient
/// PageView's own controller via Scrollable.of(context), since there is no
/// other route to that signal without editing library_screen.dart — has a
/// real PageController to observe.
Future<PageController> _pumpWithRealPager(WidgetTester tester, ProviderContainer c) async {
  final controller = PageController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(
        body: PageView(
          controller: controller,
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            SizedBox.expand(child: Text('Todo')),
            SizedBox.expand(child: Text('Carpetas')),
            PlaylistsTab(),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  // Land on Listas (index 2), same as tapping the chip in the real app.
  controller.jumpToPage(2);
  await tester.pumpAndSettle();
  return controller;
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

      expect(find.text('Borrar'), findsNothing);

      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();

      expect(find.text('Borrar'), findsOneWidget);
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

      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();
      expect(find.text('Borrar'), findsOneWidget);

      await tester.tap(find.text('Serie'));
      await tester.pumpAndSettle();

      expect(find.text('Borrar'), findsNothing);
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

      expect(find.text('Borrar'), findsNothing);
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

      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Curso'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Borrar').first);
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

      await tester.tap(find.text('Borrar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Borrar')));
      await tester.pumpAndSettle();

      expect(store.all(), isEmpty);
      // The selection bar is gone — nothing left to select.
      expect(find.text('Borrar'), findsNothing);
    });

    testWidgets('leaving the Listas tab clears the selection', (tester) async {
      final c = await twoPlaylists();
      addTearDown(c.dispose);
      final controller = await _pumpWithRealPager(tester, c);

      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();
      expect(find.text('Borrar'), findsOneWidget);

      controller.jumpToPage(0);
      await tester.pumpAndSettle();

      controller.jumpToPage(2);
      await tester.pumpAndSettle();

      expect(find.text('Borrar'), findsNothing);
    });
  });
}
