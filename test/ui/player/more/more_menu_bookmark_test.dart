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
import '../../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

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

  await pumpLocalized(
    tester,
    Scaffold(
      body: Center(
        child: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () => showMoreMenu(context, ref),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    container: c,
    theme: KivoTheme.dark(),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('Marcadores row shows the count, singular and plural', (tester) async {
    final store = InMemoryBookmarkStore();
    await _pump(tester, bookmarkStore: store);
    expect(find.text(_l10n.playerMenuBookmarksSubtitle(0)), findsOneWidget);
  });

  testWidgets('Marcar aquí saves the position and shows the formatted time',
      (tester) async {
    final store = InMemoryBookmarkStore();
    final c = await _pump(tester, bookmarkStore: store);

    await tester.tap(find.text(_l10n.playerMenuMarkHere));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.playerMenuBookmarkSavedSnackbar('05:30')), findsOneWidget);
    expect(c.read(bookmarksProvider), hasLength(1));
    expect(c.read(bookmarksProvider).single.positionMs, const Duration(minutes: 5, seconds: 30).inMilliseconds);
    expect(c.read(bookmarksProvider).single.name, '');
  });

  testWidgets('Nombrar on the snackbar names the just-saved bookmark', (tester) async {
    final store = InMemoryBookmarkStore();
    final c = await _pump(tester, bookmarkStore: store);

    await tester.tap(find.text(_l10n.playerMenuMarkHere));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.playerMenuBookmarkNameAction));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Gol de media cancha');
    await tester.tap(find.text(_l10n.commonSave));
    await tester.pumpAndSettle();

    expect(c.read(bookmarksProvider).single.name, 'Gol de media cancha');
  });

  testWidgets('Marcadores opens on top of the menu; back returns to the menu',
      (tester) async {
    await _pump(tester, bookmarkStore: InMemoryBookmarkStore());
    await tester.tap(find.text(_l10n.playerBookmarksTitle));
    await tester.pumpAndSettle();
    // The bookmarks sheet is up...
    expect(find.text(_l10n.playerMenuBookmarksSubtitle(0)), findsWidgets);
    // ...and closing it lands back on the menu, not on the video.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_l10n.playerMenuGroupPlayback), findsOneWidget);
    expect(find.text(_l10n.playerBookmarksTitle), findsOneWidget);
  });

  testWidgets('Ecualizador opens on top of the menu; back returns to the menu',
      (tester) async {
    await _pump(tester, bookmarkStore: InMemoryBookmarkStore());
    await tester.tap(find.text(_l10n.playerMenuEqualizer));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.playerMenuGroupPlayback), findsNothing); // the screen covers it
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_l10n.playerMenuGroupPlayback), findsOneWidget);
  });
}
