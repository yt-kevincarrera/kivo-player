import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/folder_screen.dart';
import 'package:kivo_player/ui/home/library_screen.dart';
import 'package:kivo_player/ui/home/state/library_filter_state.dart';
import '../../fakes/fakes.dart';

/// A permission stub whose `status()` is fixed and whose `request()` is
/// counted — the empty state for [MediaAccess.limited] must be able to send
/// the user back to the system picker to widen the selection.
class _Perm implements MediaPermission {
  _Perm(this._access);
  final MediaAccess _access;
  int requests = 0;

  @override
  Future<MediaAccess> status() async => _access;

  @override
  Future<MediaAccess> request() async {
    requests++;
    return _access;
  }
}

const _videos = [
  VideoItem(
    id: '1',
    uri: 'content://1',
    name: 'Inception.mp4',
    folder: 'Movies',
    durationMs: 90000,
    sizeBytes: 1,
    dateAddedMs: 1,
  ),
  VideoItem(
    id: '2',
    uri: 'content://2',
    name: 'Avatar.mp4',
    folder: 'Downloads',
    durationMs: 120000,
    sizeBytes: 1,
    dateAddedMs: 1,
  ),
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Widget home,
  required FakeMediaIndexer indexer,
  required _Perm perm,
  Set<String> played = const {},
}) async {
  final settingsService = await SettingsService.load(InMemorySettingsStore());
  final playedStore = InMemoryPlayedStore();
  for (final key in played) {
    await playedStore.markPlayed(key);
  }

  final container = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(settingsService),
      mediaPermissionImplProvider.overrideWithValue(perm),
      mediaIndexerProvider.overrideWithValue(indexer),
      resumeServiceProvider.overrideWithValue(
        ResumeService(InMemoryResumeStore()),
      ),
      playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      playedStoreProvider.overrideWithValue(playedStore),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: KivoTheme.light(), home: home),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a device with no videos shows the empty state, not a blank body',
      (tester) async {
    await _pump(
      tester,
      home: const LibraryScreen(),
      indexer: FakeMediaIndexer(const []),
      perm: _Perm(MediaAccess.granted),
    );

    expect(find.text('Todavía no hay videos'), findsOneWidget);
    expect(find.text('Abrir archivo'), findsOneWidget);
    expect(find.text('Volver a buscar'), findsOneWidget);
  });

  testWidgets('"Volver a buscar" re-scans the media index', (tester) async {
    final indexer = FakeMediaIndexer(const []);
    await _pump(
      tester,
      home: const LibraryScreen(),
      indexer: indexer,
      perm: _Perm(MediaAccess.granted),
    );
    expect(indexer.scans, 1);

    await tester.tap(find.text('Volver a buscar'));
    await tester.pumpAndSettle();

    expect(indexer.scans, 2);
  });

  testWidgets('limited access offers to widen the selection', (tester) async {
    final perm = _Perm(MediaAccess.limited);
    await _pump(
      tester,
      home: const LibraryScreen(),
      indexer: FakeMediaIndexer(const []),
      perm: perm,
    );

    expect(find.text('Kivo solo ve los videos que elegiste'), findsOneWidget);

    await tester.tap(find.text('Elegir más videos'));
    await tester.pumpAndSettle();

    expect(perm.requests, 1);
  });

  testWidgets('"No vistos" hiding every video shows the all-watched state',
      (tester) async {
    final container = await _pump(
      tester,
      home: const LibraryScreen(),
      indexer: FakeMediaIndexer(_videos),
      perm: _Perm(MediaAccess.granted),
      played: {'Inception.mp4', 'Avatar.mp4'},
    );

    container.read(libraryUnwatchedOnlyProvider.notifier).state = true;
    await tester.pumpAndSettle();

    // Distinct from "no videos at all" — the videos exist, the filter hides
    // them, so the way out is dropping the filter rather than opening a file.
    expect(find.text('Ya viste todo'), findsOneWidget);
    expect(find.text('Todavía no hay videos'), findsNothing);

    await tester.tap(find.text('Quitar filtro'));
    await tester.pumpAndSettle();

    expect(container.read(libraryUnwatchedOnlyProvider), false);
    expect(find.text('Inception.mp4'), findsOneWidget);
  });

  testWidgets('a search with no hits offers to drop the query', (tester) async {
    final container = await _pump(
      tester,
      home: const LibraryScreen(),
      indexer: FakeMediaIndexer(_videos),
      perm: _Perm(MediaAccess.granted),
    );

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pumpAndSettle();

    expect(
      find.text('No se encontraron videos para "zzz-no-match"'),
      findsOneWidget,
    );

    await tester.tap(find.text('Borrar búsqueda'));
    await tester.pumpAndSettle();

    expect(container.read(librarySearchActiveProvider), false);
    expect(find.text('Inception.mp4'), findsOneWidget);
  });

  testWidgets('the Carpetas tab with no folders shows the empty state',
      (tester) async {
    await _pump(
      tester,
      home: const LibraryScreen(),
      indexer: FakeMediaIndexer(const []),
      perm: _Perm(MediaAccess.granted),
    );

    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();

    expect(find.text('No hay carpetas'), findsOneWidget);
  });

  testWidgets('a folder emptied by deleting its last video shows the state',
      (tester) async {
    // The index no longer holds anything in "Movies" — the same situation as
    // deleting the folder's last video from inside FolderScreen.
    await _pump(
      tester,
      home: const FolderScreen(folder: 'Movies', videos: []),
      indexer: FakeMediaIndexer(const []),
      perm: _Perm(MediaAccess.granted),
    );

    expect(find.text('Esta carpeta quedó vacía'), findsOneWidget);
  });
}
