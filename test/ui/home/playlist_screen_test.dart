// test/ui/home/playlist_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/playlists/playlist_screen.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/thumbnail_image.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

/// Every row's ⋮ / options icon now lives inside a reused `VideoTile` (or,
/// for an unavailable entry, the hand-matched row that mirrors it) rather
/// than behind a dedicated `playlist-remove-N` key — this locates it by
/// scoping to the row's own key first, so it stays index-specific.
Finder _optionsButton(int index) => find.descendant(
      of: find.byKey(ValueKey('playlist-entry-$index')),
      matching: find.byIcon(Icons.close),
    );

/// The drag grip at the START of row [index] — the only drag target now
/// that `buildDefaultDragHandles` is false.
Finder _grip(int index) => find.descendant(
      of: find.byKey(ValueKey('playlist-entry-$index')),
      matching: find.byIcon(Icons.drag_handle),
    );

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

// Copy the media-index overrides from an existing library test.
Future<ProviderContainer> _c(PlaylistStore store, List<VideoItem> index) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  var tick = 0;
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(index)),
    mediaPermissionImplProvider.overrideWithValue(_GrantedPerm()),
    playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
    resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
    frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
    playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    playlistStoreProvider.overrideWithValue(store),
    playlistClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
  ]);
}

/// Mounts [PlaylistScreen] behind a real pushed route (rather than as
/// `MaterialApp.home`) so tests that need the screen to actually POP —
/// deleting the playlist you're looking at — have something to pop to.
Future<void> _pushScreen(WidgetTester tester, ProviderContainer c, String playlistId) async {
  await pumpLocalized(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlaylistScreen(playlistId: playlistId),
            )),
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
  testWidgets('lists the entries in playlist order', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('2', 'b.mkv'), _v('1', 'a.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();

    final rows = tester.widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(rows.indexOf('b.mkv') < rows.indexOf('a.mkv'), true);
  });

  testWidgets('a missing video is shown and marked, not hidden', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, const []); // nothing on the device
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();

    expect(find.text('a.mkv'), findsOneWidget);
    expect(find.textContaining('No disponible'), findsOneWidget);
  });

  testWidgets('tapping a missing entry does not start playback', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, const []);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();
    await tester.tap(find.text('a.mkv'));
    await tester.pumpAndSettle();

    expect(c.read(currentVideoProvider), isNull);
  });

  testWidgets('an available entry shows its video thumbnail', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();

    final thumb = tester.widget<ThumbnailImage>(find.byType(ThumbnailImage));
    expect(thumb.id, '1');
  });

  testWidgets(
      'an unavailable entry shows the coverless-playlist placeholder, not a thumbnail',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, const []); // nothing on the device
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();

    expect(find.byType(ThumbnailImage), findsNothing);
    // Same placeholder icon the Listas tab uses for a coverless playlist.
    expect(find.byIcon(Icons.playlist_play_rounded), findsOneWidget);
  });

  testWidgets('removing an entry takes it off the screen', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();

    await tester.tap(_optionsButton(0));
    await tester.pumpAndSettle();

    expect(find.text('a.mkv'), findsNothing);
    expect(store.all().single.entries, isEmpty);
  });

  testWidgets('removing an entry offers Deshacer, which restores it at its original index',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(
        p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();

    // Remove the MIDDLE entry — proves undo restores position, not just presence.
    await tester.tap(_optionsButton(1));
    await tester.pumpAndSettle();

    expect(find.text('b.mkv'), findsNothing);
    expect(store.all().single.entries.map((e) => e.displayName), ['a.mkv', 'c.mkv']);
    expect(find.text(_l10n.commonUndo), findsOneWidget);

    await tester.tap(find.text(_l10n.commonUndo));
    await tester.pumpAndSettle();

    expect(store.all().single.entries.map((e) => e.displayName),
        ['a.mkv', 'b.mkv', 'c.mkv']);
  });

  testWidgets('removing entries quickly does not queue multiple snackbars',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(
        p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();

    // Remove three entries back-to-back without letting any snackbar settle.
    await tester.tap(_optionsButton(0));
    await tester.pump();
    await tester.tap(_optionsButton(0));
    await tester.pump();
    await tester.tap(_optionsButton(0));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });

  group('reorder — both drag directions', () {
    // Flutter's ReorderableListView reports newIndex as the position in the
    // list BEFORE the dragged item is removed. Dragging item 0 to the very
    // end therefore reports newIndex == length (one past the last valid
    // final index), not length - 1. The screen must subtract one in that
    // case before calling PlaylistsNotifier.reorder, which treats newIndex
    // as the FINAL position. Only the downward direction needs the
    // adjustment — this is what makes it easy to get one direction right
    // and the other wrong.

    testWidgets('dragging DOWN (Flutter over-reports newIndex by one)',
        (tester) async {
      final store = InMemoryPlaylistStore();
      final c = await _c(store, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);
      addTearDown(c.dispose);
      await c.read(mediaIndexProvider.future);
      final p = await c.read(playlistsProvider.notifier).create('Serie');
      await c.read(playlistsProvider.notifier).addVideos(
          p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);

      await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
      await tester.pumpAndSettle();

      final list = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
      // Dragging entry 0 ("a.mkv") past the end: Flutter reports newIndex 3
      // (== length), not 2 (the actual final index).
      list.onReorder(0, 3);
      await tester.pumpAndSettle();

      expect(store.all().single.entries.map((e) => e.displayName),
          ['b.mkv', 'c.mkv', 'a.mkv']);
    });

    testWidgets('dragging UP (newIndex is already the final position)',
        (tester) async {
      final store = InMemoryPlaylistStore();
      final c = await _c(store, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);
      addTearDown(c.dispose);
      await c.read(mediaIndexProvider.future);
      final p = await c.read(playlistsProvider.notifier).create('Serie');
      await c.read(playlistsProvider.notifier).addVideos(
          p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);

      await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
      await tester.pumpAndSettle();

      final list = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
      // Dragging entry 2 ("c.mkv") to the top: Flutter already reports the
      // correct final index (0) when dragging upward.
      list.onReorder(2, 0);
      await tester.pumpAndSettle();

      expect(store.all().single.entries.map((e) => e.displayName),
          ['c.mkv', 'a.mkv', 'b.mkv']);
    });
  });

  testWidgets('tapping a playlist row opens its screen and pushes the player',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();
    // Deliberately no pumpAndSettle after this tap: the row's onTap runs
    // synchronously (playAt + Navigator.push), and settling the pushed
    // route would build the real PlayerScreen, which needs a much larger
    // provider stack than this playlist-screen test owns. The session
    // state is enough to prove the row opened the right video.
    await tester.tap(find.text('a.mkv'));

    expect(c.read(currentVideoProvider), isNotNull);
    expect(c.read(currentVideoProvider)!.displayName, 'a.mkv');
  });

  testWidgets('deleting the playlist asks to confirm and names what it destroys',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, const []);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Curso de cocina');

    await _pushScreen(tester, c, p.id);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.playlistDeleteTitle));
    await tester.pumpAndSettle();

    // Names the playlist and says it cannot be undone (spec: destructive
    // actions need a confirm that says what they destroy).
    expect(find.textContaining('Curso de cocina'), findsWidgets);
    expect(find.textContaining('no se puede deshacer'), findsOneWidget);

    // Cancel leaves the playlist untouched.
    await tester.tap(find.text(_l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(store.all().single.name, 'Curso de cocina');
  });

  testWidgets('deleting the playlist you are viewing pops the screen instead of crashing',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, const []);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');

    await _pushScreen(tester, c, p.id);
    expect(find.byType(PlaylistScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.playlistDeleteTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.commonDelete));
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistScreen), findsNothing);
    expect(store.all(), isEmpty);
  });

  testWidgets('renaming the playlist updates its title, blank is refused',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, const []);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.playlistRenameTitle));
    await tester.pumpAndSettle();

    // A blank name is refused — the dialog stays open.
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text(_l10n.commonSave));
    await tester.pumpAndSettle();
    expect(store.all().single.name, 'Serie');

    await tester.enterText(find.byType(TextField), 'Otra serie');
    await tester.tap(find.text(_l10n.commonSave));
    await tester.pumpAndSettle();

    expect(store.all().single.name, 'Otra serie');
    expect(find.text('Otra serie'), findsWidgets);
  });

  testWidgets('long-pressing an available entry marks it, shown via the selection app bar',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();

    await tester.longPress(find.text('a.mkv'));
    await tester.pumpAndSettle();

    expect(c.read(librarySelectionProvider), {'content://1'});
    // The normal AppBar (playlist name + rename/delete menu) is swapped for
    // the shared SelectionAppBar while marking is active.
    expect(find.text(_l10n.selectionCountLabel(1)), findsOneWidget);
    expect(find.text('Serie'), findsNothing);

    // Tapping the second (unmarked) entry while marking is active toggles
    // its mark too, instead of opening it.
    await tester.tap(find.text('b.mkv'));
    await tester.pumpAndSettle();
    expect(c.read(librarySelectionProvider), {'content://1', 'content://2'});
    expect(c.read(currentVideoProvider), isNull);
  });

  testWidgets('an unavailable entry cannot be marked', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, const []); // nothing on the device
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();

    await tester.longPress(find.text('a.mkv'));
    await tester.pumpAndSettle();

    expect(c.read(librarySelectionProvider), isEmpty);
    // Still the normal AppBar — long-pressing an unavailable row never
    // entered selection mode.
    expect(find.text('Serie'), findsOneWidget);
  });

  testWidgets('dragging the grip reorders; the rest of the row no longer drags',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(
        p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);

    await pumpLocalized(tester, PlaylistScreen(playlistId: p.id), container: c);
    await tester.pumpAndSettle();

    // A single one-shot drag() only registers one swap with
    // ReorderableListView — its drag proxy tracks the pointer's motion
    // incrementally, frame by frame, the way a real drag arrives. Stepping
    // the move (and pumping between steps) mimics that and carries the item
    // all the way to the end, matching the other reorder tests' expectation
    // that dragging item 0 past the end lands it last.
    final gesture = await tester.startGesture(tester.getCenter(_grip(0)));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(store.all().single.entries.map((e) => e.displayName),
        ['b.mkv', 'c.mkv', 'a.mkv']);
  });
}
