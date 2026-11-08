import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/library/continue_watching.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/ui/home/library_screen.dart';
import 'package:kivo_player/ui/home/playlists/playlists_tab.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

class _GrantedPerm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

class _RecordingFilePicker extends FilePicker {
  FileType? requestedType;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    requestedType = type;
    return null;
  }
}

/// A fixed timestamp so groupByDay produces a predictable label.
/// The videos are created with dateAddedMs = 1 (1970-01-01), which will
/// produce a "1 ene" section header relative to any near-modern "now".
final _videos = [
  const VideoItem(
    id: '1',
    uri: 'content://1',
    name: 'Inception.mp4',
    folder: 'Movies',
    durationMs: 90000,
    sizeBytes: 1,
    dateAddedMs: 1,
  ),
  const VideoItem(
    id: '2',
    uri: 'content://2',
    name: 'Avatar.mp4',
    folder: 'Downloads',
    durationMs: 120000,
    sizeBytes: 1,
    dateAddedMs: 1,
  ),
];

Future<ProviderContainer> _buildApp(WidgetTester tester) async {
  final settingsService = await SettingsService.load(InMemorySettingsStore());
  final fake = FakeMediaIndexer(_videos);
  final resumeStore = InMemoryResumeStore();
  final engine = FakePlaybackEngine();
  // Deterministic playlist ids/timestamps, same pattern as
  // test/player/playlists/playlist_controller_test.dart — a couple of the
  // tests below create playlists in quick succession and need distinct
  // createdAtMs to assert on ordering.
  var tick = 0;

  final container = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(settingsService),
      mediaPermissionImplProvider.overrideWithValue(_GrantedPerm()),
      mediaIndexerProvider.overrideWithValue(fake),
      resumeServiceProvider.overrideWithValue(ResumeService(resumeStore)),
      playbackEngineProvider.overrideWithValue(engine),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      playlistStoreProvider.overrideWithValue(InMemoryPlaylistStore()),
      playlistClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++),
      ),
    ],
  );
  var theme = KivoTheme.light();
  final fontPath = Platform.environment['KIVO_VISUAL_FONT'];
  if (fontPath != null) {
    await tester.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader('KivoVisual')
            ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView)))
          .load();
    });
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'KivoVisual'),
    );
  }
  await pumpLocalized(
    tester,
    const LibraryScreen(),
    theme: theme,
    container: container,
    captureKey: Platform.environment['KIVO_SCREENSHOT_DIR'] == null
        ? null
        : const Key('watch-filter-capture'),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    for (final name in [
      'receive_sharing_intent/messages',
      'receive_sharing_intent/events-media',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
  });
  tearDownAll(() {
    for (final name in [
      'receive_sharing_intent/messages',
      'receive_sharing_intent/events-media',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        null,
      );
    }
  });
  testWidgets(
    'status menu filters real progress and completion and composes with search',
    (tester) async {
      final container = await _buildApp(tester);
      addTearDown(container.dispose);
      final resume = container.read(resumeServiceProvider);
      await resume.record(
        _videos[0].key,
        const Duration(seconds: 30),
        const Duration(seconds: 90),
        1,
      );
      await resume.record(
        _videos[1].key,
        const Duration(seconds: 120),
        const Duration(seconds: 120),
        2,
      );
      container.invalidate(continueWatchingProvider);
      container.invalidate(playedKeysProvider);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      final captureDirectory = Platform.environment['KIVO_SCREENSHOT_DIR'];
      if (captureDirectory != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('watch-filter-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory(captureDirectory)
            ..createSync(recursive: true);
          await File(
            '${directory.path}/watch-status-menu.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('En curso'));
      await tester.pumpAndSettle();
      expect(find.text('Inception.mp4'), findsOneWidget);
      expect(find.text('Avatar.mp4'), findsNothing);
      await tester.tap(find.byIcon(Icons.filter_list_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terminados'));
      await tester.pumpAndSettle();
      expect(find.text('Inception.mp4'), findsNothing);
      expect(find.text('Avatar.mp4'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'inception');
      await tester.pumpAndSettle();
      expect(find.text('Quitar filtro'), findsOneWidget);
      await tester.tap(find.text('Quitar filtro'));
      await tester.pumpAndSettle();
      expect(find.text('Inception.mp4'), findsOneWidget);
      expect(find.text('Avatar.mp4'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('open file allows video containers with non-video MIME types', (
    tester,
  ) async {
    final picker = _RecordingFilePicker();
    FilePicker.platform = picker;
    addTearDown(FilePickerIO.registerWith);
    final container = await _buildApp(tester);
    addTearDown(container.dispose);

    await tester.tap(find.byTooltip('Abrir archivo'));
    await tester.pumpAndSettle();

    expect(picker.requestedType, FileType.any);
    expect(container.read(currentVideoProvider), isNull);
    expect(find.text('Inception.mp4'), findsOneWidget);
  });

  testWidgets('Kivo wordmark is shown in the AppBar', (tester) async {
    await _buildApp(tester);

    expect(find.text('Kivo'), findsOneWidget);
  });

  testWidgets('Todo chip is shown', (tester) async {
    await _buildApp(tester);

    expect(find.text('Todo'), findsOneWidget);
  });

  testWidgets('Todo tab shows known video name under a date section header', (
    tester,
  ) async {
    await _buildApp(tester);

    // The default tab is Todo (index 0). At least one video name must appear.
    expect(find.text('Inception.mp4'), findsOneWidget);
    expect(find.text('Avatar.mp4'), findsOneWidget);
  });

  testWidgets('Tapping Carpetas tab shows folder names', (tester) async {
    await _buildApp(tester);

    // Tap the "Carpetas" filter chip
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();

    // Both folder names should appear as folder cards
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
  });

  testWidgets('Todo tab is shown by default (video names visible)', (
    tester,
  ) async {
    await _buildApp(tester);

    // In Todo tab the video names should be visible.
    expect(find.text('Inception.mp4'), findsOneWidget);
  });

  testWidgets('Switching back from Carpetas to Todo restores video list', (
    tester,
  ) async {
    await _buildApp(tester);

    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Movies'), findsOneWidget);

    await tester.tap(find.text('Todo'));
    await tester.pumpAndSettle();
    expect(find.text('Inception.mp4'), findsOneWidget);
  });

  testWidgets('tapping search shows a text field and hides the title', (
    tester,
  ) async {
    await _buildApp(tester);
    expect(find.text('Kivo'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('Kivo'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typing a query filters to matching videos', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump();

    expect(find.text('Inception.mp4'), findsOneWidget);
    expect(find.text('Avatar.mp4'), findsNothing);
  });

  testWidgets('search matches by folder name too', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'downloads');
    await tester.pump();

    expect(find.text('Avatar.mp4'), findsOneWidget);
    expect(find.text('Inception.mp4'), findsNothing);
  });

  testWidgets('closing search restores the title and clears the query', (
    tester,
  ) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Kivo'), findsOneWidget);
    expect(find.text('Inception.mp4'), findsOneWidget);
    expect(find.text('Avatar.mp4'), findsOneWidget);
  });

  testWidgets('no search matches shows the empty message', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pump();

    expect(
      find.text('No se encontraron videos para "zzz-no-match"'),
      findsOneWidget,
    );
  });

  testWidgets('sort menu changes order to alphabetical', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nombre A-Z'));
    await tester.pumpAndSettle();

    final avatarCenter = tester.getCenter(find.text('Avatar.mp4'));
    final inceptionCenter = tester.getCenter(find.text('Inception.mp4'));
    expect(
      avatarCenter.dy < inceptionCenter.dy ||
          (avatarCenter.dy == inceptionCenter.dy &&
              avatarCenter.dx < inceptionCenter.dx),
      isTrue,
    );
  });

  testWidgets('"No vistos" chip is hidden on the Carpetas tab', (tester) async {
    await _buildApp(tester);
    expect(find.byIcon(Icons.filter_list), findsOneWidget);

    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.filter_list), findsNothing);
  });

  testWidgets(
    'switching to Carpetas while a video is selected clears the selection',
    (tester) async {
      final container = await _buildApp(tester);
      addTearDown(container.dispose);

      // Enter selection mode via long-press on a video tile.
      await tester.longPress(find.byType(VideoTile).first);
      await tester.pumpAndSettle();
      expect(container.read(librarySelectionProvider), isNotEmpty);
      expect(find.byIcon(Icons.select_all), findsOneWidget);

      // Switch to the Carpetas sub-tab: the orphaned selection must be
      // cleared, otherwise SelectionAppBar reverts to the normal AppBar
      // while the selection provider stays non-empty (invisible + PopScope
      // then swallows the next back press).
      await tester.tap(find.byIcon(Icons.folder_outlined));
      await tester.pumpAndSettle();

      expect(container.read(librarySelectionProvider), isEmpty);
      expect(find.byIcon(Icons.select_all), findsNothing);
    },
  );
  testWidgets('tab labels and bounds stay stable throughout selection', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _buildApp(tester);

    Rect chipBounds(IconData icon) => tester.getRect(
      find
          .ancestor(of: find.byIcon(icon), matching: find.byType(InkWell))
          .first,
    );

    final before = chipBounds(Icons.folder_outlined);

    await tester.tap(find.byIcon(Icons.folder_outlined));
    for (final elapsed in [16, 80, 160]) {
      await tester.pump(Duration(milliseconds: elapsed));
      expect(chipBounds(Icons.folder_outlined), before);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(chipBounds(Icons.folder_outlined), before);
    expect(find.text('Todo'), findsOneWidget);
    expect(find.text('Carpetas'), findsOneWidget);
    expect(find.text('Listas'), findsOneWidget);
  });

  testWidgets('the icon-only chips still announce themselves to a reader', (
    tester,
  ) async {
    // An icon with no text has to carry its name in semantics or a screen
    // reader gets nothing at all.
    final handle = tester.ensureSemantics();
    await _buildApp(tester);

    expect(find.bySemanticsLabel('Carpetas'), findsOneWidget);
    expect(find.bySemanticsLabel('Listas'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('leaving the Listas tab clears the playlists marked in it', (
    tester,
  ) async {
    // The pager keeps every sub-tab alive, so marks left behind would sit
    // there with their bar gone and reappear on return. Marking is the tab's
    // own gesture; what this covers is that the screen owning the pager is
    // the one that clears them.
    final container = await _buildApp(tester);
    addTearDown(container.dispose);

    container.read(playlistsSelectionProvider.notifier).toggle('cualquiera');
    expect(container.read(playlistsSelectionProvider), isNotEmpty);

    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();

    expect(container.read(playlistsSelectionProvider), isEmpty);
  });

  testWidgets(
    'typing in the search field while on Listas filters playlists and does not show video tiles',
    (tester) async {
      final container = await _buildApp(tester);
      addTearDown(container.dispose);
      await container.read(playlistsProvider.notifier).create('Series');
      await container.read(playlistsProvider.notifier).create('Cursos');

      // Switch to the Listas sub-tab first.
      await tester.tap(find.byIcon(Icons.queue_music_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Series'), findsOneWidget);
      expect(find.text('Cursos'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'cur');
      await tester.pump();

      expect(find.text('Cursos'), findsOneWidget);
      expect(find.text('Series'), findsNothing);
      // The search view on Listas is the playlist list, not the video feed —
      // no video tile should ever appear while it's showing.
      expect(find.byType(VideoTile), findsNothing);
      expect(find.text('Inception.mp4'), findsNothing);
      expect(find.text('Avatar.mp4'), findsNothing);
    },
  );

  testWidgets('search hint says "listas" on the Listas tab, videos elsewhere', (
    tester,
  ) async {
    await _buildApp(tester);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      'Buscar videos o carpetas',
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.queue_music_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      'Buscar listas',
    );
  });

  testWidgets('opening search from the Listas tab clears any playlist marks', (
    tester,
  ) async {
    // Mirrors the sub-tab-switch test above: search replaces the visible
    // rows with a filtered set too, so a mark left behind is the same
    // orphaned-selection bug, just reached from the search icon instead.
    final container = await _buildApp(tester);
    addTearDown(container.dispose);
    await container.read(playlistsProvider.notifier).create('Serie');

    await tester.tap(find.byIcon(Icons.queue_music_outlined));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Serie'));
    await tester.pumpAndSettle();
    expect(container.read(playlistsSelectionProvider), isNotEmpty);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(container.read(playlistsSelectionProvider), isEmpty);
  });

  testWidgets(
    'bulk Borrar on Listas only deletes playlists a search query still shows',
    (tester) async {
      final container = await _buildApp(tester);
      addTearDown(container.dispose);
      await container.read(playlistsProvider.notifier).create('Serie');
      await container.read(playlistsProvider.notifier).create('Curso');

      await tester.tap(find.byIcon(Icons.queue_music_outlined));
      await tester.pumpAndSettle();

      // Open search first (selection is already empty, so nothing to clear),
      // THEN mark both rows while the query is still empty — search shows
      // every playlist until something is typed.
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Serie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Curso'));
      await tester.pumpAndSettle();
      expect(container.read(playlistsSelectionProvider).length, 2);

      // Narrowing the query hides Curso's row without touching its mark.
      await tester.enterText(find.byType(TextField), 'serie');
      await tester.pump();
      expect(find.text('Serie'), findsOneWidget);
      expect(find.text('Curso'), findsNothing);

      await tester.tap(find.byKey(const Key('playlists-bulk-borrar')));
      await tester.pumpAndSettle();
      // The confirm dialog names only the one still visible, not both marked.
      expect(find.textContaining('¿Borrar 1 lista?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Borrar'),
        ),
      );
      await tester.pumpAndSettle();

      // Curso survives — it was marked but never shown once the query hid it.
      expect(container.read(playlistsProvider).map((p) => p.name).toList(), [
        'Curso',
      ]);
    },
  );

  testWidgets(
    'Borrar búsqueda on the Listas empty state fully closes search, like the videos one',
    (tester) async {
      final container = await _buildApp(tester);
      addTearDown(container.dispose);
      await container.read(playlistsProvider.notifier).create('Serie');

      await tester.tap(find.byIcon(Icons.queue_music_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzz-no-match');
      await tester.pump();

      expect(
        find.textContaining('Ninguna lista coincide con "zzz-no-match"'),
        findsOneWidget,
      );

      await tester.tap(find.text('Borrar búsqueda'));
      await tester.pumpAndSettle();

      // Same escape hatch as the videos search empty state: the field is
      // gone, the title is back, and the full playlist list is showing again
      // (not just an emptied query with the field still open).
      expect(find.text('Kivo'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Serie'), findsOneWidget);
    },
  );

  testWidgets('changing the sort menu on Listas reorders the rows', (
    tester,
  ) async {
    final container = await _buildApp(tester);
    addTearDown(container.dispose);
    // Created in this order, so "recent" (the default) puts Zulu — made
    // second — above Alfa, while "Nombre A-Z" would put Alfa above Zulu:
    // the two sorts disagree, so a reorder actually proves the sort changed.
    await container.read(playlistsProvider.notifier).create('Alfa');
    await container.read(playlistsProvider.notifier).create('Zulu');

    await tester.tap(find.byIcon(Icons.queue_music_outlined));
    await tester.pumpAndSettle();

    final beforeZulu = tester.getCenter(find.text('Zulu'));
    final beforeAlfa = tester.getCenter(find.text('Alfa'));
    expect(beforeZulu.dy, lessThan(beforeAlfa.dy));

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nombre A-Z'));
    await tester.pumpAndSettle();

    final afterZulu = tester.getCenter(find.text('Zulu'));
    final afterAlfa = tester.getCenter(find.text('Alfa'));
    expect(afterAlfa.dy, lessThan(afterZulu.dy));
  });
}
