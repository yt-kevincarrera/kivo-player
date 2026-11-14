import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/storage_browser.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/storage_browser_provider.dart';
import 'package:kivo_player/platform/television_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/tv/tv_library_screen.dart';
import 'package:kivo_player/ui/tv/tv_settings_screen.dart';
import 'package:kivo_player/ui/tv/tv_storage_screen.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _videos = List.generate(
  8,
  (i) => VideoItem(
    id: '$i',
    uri: 'file:///storage/usb/video$i.mkv',
    name: [
      'Entre montañas.mkv',
      'El bosque vivo.mp4',
      'Días junto al mar.mp4',
      'Más allá de las dunas.avi',
    ][i % 4],
    folder: 'Documentales',
    durationMs: 600000,
    sizeBytes: 102400000,
    dateAddedMs: i,
  ),
);

class _Storage extends StorageBrowser {
  bool denied = false;
  @override
  Future<List<StorageVolume>> volumes() async => [
    const StorageVolume(
      path: '/storage/usb',
      name: 'Kingston USB',
      removable: true,
    ),
  ];
  @override
  Future<List<StorageEntry>> list(String path) async {
    if (denied) throw PlatformException(code: 'ACCESS_DENIED');
    return path == '/storage/usb'
        ? [
            const StorageEntry(
              path: '/storage/usb/Películas',
              name: 'Películas',
              directory: true,
            ),
          ]
        : [
            StorageEntry(
              path: '/storage/usb/Películas/movie.mkv',
              name: 'movie.mkv',
              directory: false,
              video: _videos.first,
            ),
          ];
  }

  @override
  Future<List<VideoItem>> scanRemovable() async => [];
  @override
  Future<Uint8List?> thumbnail(String path) async => null;
}

class _Artwork extends FakeMediaIndexer {
  static final images = <String, Uint8List>{};
  @override
  Future<Uint8List?> thumbnail(String id) async {
    return images[[
      'mountain',
      'forest',
      'coast',
      'desert',
    ][(int.tryParse(id) ?? 0) % 4]];
  }
}

void main() {
  setUpAll(() async {
    final directory = Platform.environment['KIVO_TV_FIXTURES'];
    if (directory != null) {
      for (final name in ['mountain', 'forest', 'coast', 'desert']) {
        _Artwork.images[name] = await File(
          '$directory/$name.jpg',
        ).readAsBytes();
      }
    }
    final fonts = Platform.environment['KIVO_TV_FONT_DIR'];
    if (fonts != null) {
      await (FontLoader('Roboto')..addFont(
            File(
              '$fonts/roboto-regular.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$fonts/materialicons-regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  final captureKey = GlobalKey();
  Future<ProviderContainer> pump(
    WidgetTester t,
    Widget screen, {
    double scale = 1,
    _Storage? storage,
  }) async {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final settings = await SettingsService.load(InMemorySettingsStore());
    final resume = ResumeService(InMemoryResumeStore());
    await resume.record(
      _videos.first.key,
      const Duration(seconds: 125),
      const Duration(minutes: 10),
      123,
    );
    final c = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(settings),
        isTelevisionProvider.overrideWithValue(true),
        libraryIndexProvider.overrideWithValue(AsyncData(_videos)),
        mediaIndexerProvider.overrideWithValue(_Artwork()),
        storageBrowserProvider.overrideWithValue(storage ?? _Storage()),
        storageChangesProvider.overrideWith((ref) => const Stream.empty()),
        resumeServiceProvider.overrideWithValue(resume),
        playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      ],
    );
    addTearDown(c.dispose);
    await pumpLocalized(
      t,
      Builder(
        builder: (ctx) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: screen,
        ),
      ),
      container: c,
      theme: KivoTheme.dark().copyWith(
        textTheme: KivoTheme.dark().textTheme.apply(fontFamily: 'Roboto'),
      ),
      captureKey: captureKey,
    );
    if (_Artwork.images.isNotEmpty) {
      await t.runAsync(() async {
        for (final data in _Artwork.images.values) {
          await precacheImage(MemoryImage(data), captureKey.currentContext!);
        }
      });
    }
    await t.pumpAndSettle();
    return c;
  }

  Future<void> capture(WidgetTester t, String name) async {
    final directory = Platform.environment['KIVO_TV_CAPTURE_DIR'];
    if (directory == null) return;
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'TV library has a focused primary action and streams shelves without overflow',
    (t) async {
      await pump(t, const TvLibraryScreen());
      expect(find.text('Continuar viendo'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);
      expect(
        t
            .getSemantics(find.byKey(const Key('tv-hero-play')))
            .hasFlag(ui.SemanticsFlag.isFocused),
        isTrue,
      );
      await capture(t, 'library');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'D-pad reaches USB, restores its focus on Back, then reaches settings',
    (t) async {
      await pump(t, const TvLibraryScreen());
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.byType(TvStorageScreen), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(TvLibraryScreen), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.byType(TvSettingsScreen), findsOneWidget);
    },
  );

  testWidgets('screen reader receives the seek value and toggle state', (
    t,
  ) async {
    await pump(t, const TvSettingsScreen());
    final interval = t
        .getSemantics(find.byKey(const Key('tv-seek-setting')))
        .getSemanticsData();
    expect(interval.value, '3 s');
    final progressive = find.bySemanticsLabel(
      RegExp('Búsqueda progresiva al mantener'),
    );
    expect(
      t.getSemantics(progressive).hasFlag(ui.SemanticsFlag.isToggled),
      isTrue,
    );
  });

  testWidgets(
    'USB explorer opens folders and Back unwinds each folder before leaving',
    (t) async {
      await pump(t, const TvStorageScreen());
      await capture(t, 'usb');
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('Películas'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('movie.mkv'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Películas'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Kingston USB'), findsOneWidget);
    },
  );

  testWidgets('unreadable USB folder explains permission recovery', (t) async {
    await pump(t, const TvStorageScreen(), storage: _Storage()..denied = true);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.textContaining('Kivo necesita permiso'), findsOneWidget);
    expect(find.text('Volver a buscar'), findsWidgets);
    await capture(t, 'usb-permission');
  });

  testWidgets('TV seek interval can be changed entirely with a D-pad', (
    t,
  ) async {
    final c = await pump(t, const TvSettingsScreen());
    await capture(t, 'settings');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await c
        .read(settingsProvider.notifier)
        .set(c.read(settingsProvider).copyWith(centerSkipSeconds: 30));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).tvRemoteSeekSeconds, 5);
    expect(c.read(settingsProvider).centerSkipSeconds, 30);
  });

  testWidgets('closing TV search restores the full video shelf', (t) async {
    await pump(t, const TvLibraryScreen());
    await t.tap(find.byKey(const Key('tv-search')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'bosque');
    await t.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is TvVideoCard && w.video.id == '7'),
      findsNothing,
    );
    await t.tap(find.byKey(const Key('tv-search')));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is TvVideoCard && w.video.id == '7'),
      findsOneWidget,
    );
  });

  testWidgets('library and settings remain usable at twice the text size', (
    t,
  ) async {
    await pump(t, const TvLibraryScreen(), scale: 2);
    expect(t.takeException(), isNull);
    await capture(t, 'library-large-text');
    await t.pumpWidget(const SizedBox());
    await pump(t, const TvSettingsScreen(), scale: 2);
    expect(t.takeException(), isNull);
    await capture(t, 'settings-large-text');
  });
}
