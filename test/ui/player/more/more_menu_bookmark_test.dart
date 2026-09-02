import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/bookmarks/bookmarks_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/more/more_menu.dart';
import '../../../fakes/fakes.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required BookmarkStore bookmarkStore,
  Duration position = const Duration(minutes: 5, seconds: 30),
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

  await tester.runAsync(() async {
    c.listen(positionProvider, (_, __) {});
    engine.emitPosition(position);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: KivoTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showMoreMenu(context, ref),
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
  testWidgets('Marcadores row shows the count, singular and plural', (tester) async {
    final store = InMemoryBookmarkStore();
    await _pump(tester, bookmarkStore: store);
    expect(find.text('Sin marcadores'), findsOneWidget);
  });

  testWidgets('Marcar aquí saves the position and shows the formatted time',
      (tester) async {
    final store = InMemoryBookmarkStore();
    final c = await _pump(tester, bookmarkStore: store);

    await tester.tap(find.text('Marcar aquí'));
    await tester.pumpAndSettle();

    expect(find.text('Marcador guardado · 05:30'), findsOneWidget);
    expect(c.read(bookmarksProvider), hasLength(1));
    expect(c.read(bookmarksProvider).single.positionMs, const Duration(minutes: 5, seconds: 30).inMilliseconds);
    expect(c.read(bookmarksProvider).single.name, '');
  });

  testWidgets('Nombrar on the snackbar names the just-saved bookmark', (tester) async {
    final store = InMemoryBookmarkStore();
    final c = await _pump(tester, bookmarkStore: store);

    await tester.tap(find.text('Marcar aquí'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nombrar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Gol de media cancha');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(c.read(bookmarksProvider).single.name, 'Gol de media cancha');
  });
}
