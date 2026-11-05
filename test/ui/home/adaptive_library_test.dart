import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/l10n/generated/app_localizations.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/end_actions/pending_trash.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/library/thumbnails.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/folder_screen.dart';
import 'package:kivo_player/ui/home/home_shell.dart';
import 'package:kivo_player/ui/home/library_screen.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/folder_grid.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import 'package:kivo_player/ui/mini_player/mini_player_bar.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';

import '../../fakes/fakes.dart';

class _Granted implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

final _videos = List.generate(
  80,
  (i) => VideoItem(
    id: '$i',
    uri: 'content://adaptive/$i',
    name:
        '${['Costa adentro', 'La última estación', 'Luz de noviembre', 'Entre montañas'][i % 4]} — ${i + 1}.mp4',
    folder: i < 40 ? 'Documentales' : 'Películas',
    durationMs: 3600000,
    sizeBytes: 1800000000,
    dateAddedMs: DateTime(2026, 11, 5).millisecondsSinceEpoch,
  ),
);

Future<ProviderContainer> _mount(
  WidgetTester t,
  Size size, {
  double textScale = 1,
  bool light = false,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final service = await SettingsService.load(InMemorySettingsStore());
  final resume = InMemoryResumeStore();
  await resume.put(_videos.first.name, 840, 1);
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final frames = <Uint8List>[];
  if (Platform.environment['KIVO_SCREENSHOT_DIR'] != null) {
    await t.runAsync(() async {
      for (final sky in [
        const Color(0xFF667C80),
        const Color(0xFF766A77),
        const Color(0xFFAD9678),
        const Color(0xFF65745F),
      ]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 320, 180),
          Paint()..color = sky,
        );
        canvas.drawCircle(
          const Offset(238, 45),
          21,
          Paint()..color = const Color(0xFFCFD5CE),
        );
        canvas.drawPath(
          Path()
            ..moveTo(0, 145)
            ..lineTo(90, 47)
            ..lineTo(191, 148)
            ..lineTo(246, 86)
            ..lineTo(320, 146)
            ..lineTo(320, 180)
            ..lineTo(0, 180)
            ..close(),
          Paint()..color = const Color(0xFF3F5159),
        );
        canvas.drawPath(
          Path()
            ..moveTo(0, 156)
            ..lineTo(155, 104)
            ..lineTo(320, 161)
            ..lineTo(320, 180)
            ..lineTo(0, 180)
            ..close(),
          Paint()..color = const Color(0xFF25353C),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(320, 180);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        frames.add(data!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }
    });
  }
  final c = ProviderContainer(
    overrides: [
      if (frames.isNotEmpty)
        thumbnailProvider.overrideWith(
          (ref, id) async => frames[int.parse(id) % frames.length],
        ),
      settingsServiceProvider.overrideWithValue(service),
      pendingTrashStoreProvider.overrideWithValue(InMemoryPendingTrashStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(_videos)),
      mediaPermissionImplProvider.overrideWithValue(_Granted()),
      resumeServiceProvider.overrideWithValue(ResumeService(resume)),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
      playbackEngineProvider.overrideWithValue(engine),
    ],
  );
  addTearDown(c.dispose);
  await c.read(mediaIndexProvider.future);
  c
      .read(currentVideoProvider.notifier)
      .open(
        VideoSession(
          playbackPath: _videos.first.uri,
          displayName: _videos.first.name,
          queue: [_videos.first.uri],
          index: 0,
        ),
      );
  c.read(playerMinimizedProvider.notifier).state = true;
  var theme = light ? KivoTheme.light() : KivoTheme.dark();
  // Optional local visual evidence. CI runs the same geometry/interaction
  // assertions without relying on a machine-specific font or image baseline.
  final fontPath = Platform.environment['KIVO_VISUAL_FONT'];
  if (fontPath != null) {
    await t.runAsync(() async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final loader = FontLoader('KivoVisual')
        ..addFont(
          File(fontPath).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await loader.load();
    });
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'KivoVisual'),
    );
  }
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: const Locale('es'),
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const RepaintBoundary(
          key: Key('adaptive-capture'),
          child: HomeShell(),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  if (frames.isNotEmpty) {
    final imageContext = t.element(find.byType(HomeShell));
    await t.runAsync(
      () => Future.wait(
        frames.map((bytes) => precacheImage(MemoryImage(bytes), imageContext)),
      ),
    );
    await t.pumpAndSettle();
  }
  return c;
}

SliverGridDelegateWithFixedCrossAxisCount _videoGrid(WidgetTester t) =>
    t.widgetList<SliverGrid>(find.byType(SliverGrid)).first.gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;

Future<void> _capture(WidgetTester t, String name) async {
  final directory = Platform.environment['KIVO_SCREENSHOT_DIR'];
  if (directory == null) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('adaptive-capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('receive_sharing_intent/messages'),
      (call) async => call.method == 'getInitialMedia' ? '[]' : null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('receive_sharing_intent/events-media'),
      (call) async => null,
    );
  });
  tearDownAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('receive_sharing_intent/messages'),
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('receive_sharing_intent/events-media'),
      null,
    );
  });
  for (final scenario in [
    ('tablet-portrait', const Size(800, 1280), false),
    ('tablet-landscape', const Size(1280, 800), false),
    ('tablet-portrait-light', const Size(800, 1280), true),
    ('tablet-landscape-light', const Size(1280, 800), true),
    ('small-tablet-portrait', const Size(600, 960), false),
    ('phone', const Size(390, 844), false),
    ('small-phone', const Size(320, 640), true),
    ('phone-landscape', const Size(844, 390), false),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${scenario.$1} at ${scale}x text has accessible layouts', (
        t,
      ) async {
        final c = await _mount(
          t,
          scenario.$2,
          light: scenario.$3,
          textScale: scale,
        );
        expect(t.takeException(), isNull);
        final wide = scenario.$2.width >= 600;
        expect(
          find.byKey(const Key('home-navigation-rail')),
          wide ? findsOneWidget : findsNothing,
        );
        if (wide && scenario.$2.height >= 600 && scale == 1) {
          expect(_videoGrid(t).crossAxisCount, greaterThanOrEqualTo(2));
        }
        expect(
          t
              .getSize(
                find.descendant(
                  of: find.byType(MiniPlayerBar),
                  matching: find.byType(Dismissible),
                ),
              )
              .width,
          lessThanOrEqualTo(480),
        );
        await _capture(t, '${scenario.$1}-${scale.toInt()}x');

        await t.tap(find.byIcon(Icons.folder_outlined));
        await t.pumpAndSettle();
        expect(find.byType(FolderGrid), findsOneWidget);
        expect(t.takeException(), isNull);
        await _capture(t, '${scenario.$1}-folders-${scale.toInt()}x');

        await t.tap(find.text('Documentales').first);
        await t.pumpAndSettle();
        expect(find.byType(FolderScreen), findsOneWidget);
        t.view.physicalSize = Size(scenario.$2.height, scenario.$2.width);
        await t.pumpAndSettle();
        expect(find.byType(FolderScreen), findsOneWidget);
        expect(t.takeException(), isNull);
        expect(c.read(librarySubTabProvider), 1);
        c.read(librarySelectionProvider.notifier).toggle(_videos.first.uri);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(c.read(librarySelectionProvider), isEmpty);
        expect(find.byType(FolderScreen), findsOneWidget);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.byType(FolderScreen), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'portrait and landscape preserve search, selection, density and scroll',
    (t) async {
      final c = await _mount(t, const Size(800, 1280));
      expect(_videoGrid(t).crossAxisCount, 3);
      final libraryState = t.state(find.byType(LibraryScreen));
      final scroll = find
          .descendant(
            of: find.byType(LibraryScreen),
            matching: find.byType(CustomScrollView),
          )
          .first;
      await t.drag(scroll, const Offset(0, -400));
      await t.pumpAndSettle();
      final position = t
          .state<ScrollableState>(
            find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      final offset = position.pixels;
      expect(offset, greaterThan(0));
      t.view.physicalSize = const Size(1280, 800);
      await t.pumpAndSettle();
      expect(_videoGrid(t).crossAxisCount, 5);
      expect(t.state(find.byType(LibraryScreen)), same(libraryState));
      expect(position.pixels, offset);

      await t.tap(find.byTooltip('Vista de biblioteca'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'Compacta'));
      await t.pumpAndSettle();
      expect(_videoGrid(t).crossAxisCount, 6);
      expect(c.read(settingsProvider).libraryColumns, 1);
      expect(c.read(settingsProvider).wideLibraryDensity, 3);

      await t.tap(find.byTooltip('Buscar'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Costa');
      await t.pumpAndSettle();
      t.view.physicalSize = const Size(800, 1280);
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Costa',
      );
      c.read(librarySelectionProvider.notifier).toggle(_videos.first.uri);
      await t.pumpAndSettle();
      t.view.physicalSize = const Size(1280, 800);
      await t.pumpAndSettle();
      expect(c.read(librarySelectionProvider), contains(_videos.first.uri));
      expect(t.takeException(), isNull);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(c.read(librarySelectionProvider), isEmpty);
      expect(find.byType(VideoTile), findsWidgets);
    },
  );

  testWidgets(
    'crossing the rail breakpoint preserves the library route and one set of tools',
    (t) async {
      await _mount(t, const Size(390, 844));
      final state = t.state(find.byType(LibraryScreen));
      t.view.physicalSize = const Size(844, 390);
      await t.pumpAndSettle();
      expect(t.state(find.byType(LibraryScreen)), same(state));
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.grid_view), findsOneWidget);
      await t.tap(find.byIcon(Icons.search));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Costa');
      t.view.physicalSize = const Size(390, 844);
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Costa',
      );
      expect(t.state(find.byType(LibraryScreen)), same(state));
      expect(t.takeException(), isNull);
    },
  );
}
