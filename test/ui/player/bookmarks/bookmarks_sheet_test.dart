import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/player/bookmarks/bookmark.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/bookmarks/bookmarks_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/bookmarks/bookmarks_sheet.dart';
import '../../../fakes/fakes.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required BookmarkStore bookmarkStore,
}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    bookmarkStoreProvider.overrideWithValue(bookmarkStore),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/a.mkv',
        displayName: 'a.mkv',
        queue: ['/v/a.mkv'],
        index: 0,
      ));

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: KivoTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showBookmarksSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('no bookmarks shows the empty message', (tester) async {
    await _pump(tester, bookmarkStore: InMemoryBookmarkStore());
    expect(find.text('Todavía no marcaste nada en este video.'), findsOneWidget);
  });

  testWidgets('unnamed bookmarks show their time; named ones show name and time',
      (tester) async {
    final store = InMemoryBookmarkStore();
    await store.put('a.mkv', const [
      Bookmark(positionMs: 30000, name: '', createdAtMs: 1),
      Bookmark(positionMs: 90000, name: 'Golazo', createdAtMs: 2),
    ]);
    await _pump(tester, bookmarkStore: store);

    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('Golazo'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
  });

  testWidgets('tapping a row seeks there and closes the sheet', (tester) async {
    final store = InMemoryBookmarkStore();
    await store.put('a.mkv', const [
      Bookmark(positionMs: 45000, name: 'Escena', createdAtMs: 1),
    ]);
    final c = await _pump(tester, bookmarkStore: store);
    final engine = c.read(playbackEngineProvider) as FakePlaybackEngine;

    await tester.tap(find.text('Escena'));
    await tester.pumpAndSettle();

    expect(engine.lastSeek, const Duration(milliseconds: 45000));
    expect(find.text('Escena'), findsNothing); // sheet is gone
  });

  testWidgets('renaming a bookmark updates its row; blank is refused', (tester) async {
    final store = InMemoryBookmarkStore();
    await store.put('a.mkv', const [
      Bookmark(positionMs: 10000, name: '', createdAtMs: 1),
    ]);
    final c = await _pump(tester, bookmarkStore: store);

    await tester.tap(find.byKey(const ValueKey('bookmark-rename-0')));
    await tester.pumpAndSettle();
    // Blank is refused by not popping — the dialog stays up.
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(find.text('Nombrar marcador'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Momentazo');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Momentazo'), findsOneWidget);
    expect(c.read(bookmarksProvider).single.name, 'Momentazo');
  });

  testWidgets('deleting a bookmark removes it immediately, Deshacer restores it',
      (tester) async {
    final store = InMemoryBookmarkStore();
    await store.put('a.mkv', const [
      Bookmark(positionMs: 10000, name: 'Uno', createdAtMs: 1),
      Bookmark(positionMs: 20000, name: 'Dos', createdAtMs: 2),
    ]);
    final c = await _pump(tester, bookmarkStore: store);

    await tester.tap(find.byKey(const ValueKey('bookmark-delete-0')));
    await tester.pump();

    expect(find.text('Uno'), findsNothing);
    expect(c.read(bookmarksProvider).map((b) => b.name), ['Dos']);
    expect(find.text('Deshacer'), findsOneWidget);

    // Invoked directly rather than tapped: the SnackBar renders under the
    // still-open modal sheet, which in the small test viewport leaves its
    // action below the hit-testable area — not something the undo logic
    // itself is responsible for.
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pumpAndSettle();

    expect(c.read(bookmarksProvider).map((b) => b.name), ['Uno', 'Dos']);
  });
}
