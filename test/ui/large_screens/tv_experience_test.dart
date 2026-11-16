import 'dart:async';
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
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/storage_browser.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/storage_browser_provider.dart';
import 'package:kivo_player/platform/television_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/tv/tv_library_screen.dart';
import 'package:kivo_player/ui/tv/tv_settings_screen.dart';
import 'package:kivo_player/ui/tv/tv_panel.dart';
import 'package:kivo_player/ui/tv/tv_input_mode.dart';
import 'package:kivo_player/ui/tv/tv_storage_screen.dart';
import 'package:kivo_player/ui/home/home_shell.dart';
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
  int rescans = 0;
  bool revealOnRescan = false;
  bool indexed = false;
  @override
  Future<void> rescan(String path) async {
    rescans++;
    if (revealOnRescan) indexed = true;
  }

  List<StorageVolume>? drives;
  bool denied = false;
  bool limited = false;
  @override
  Future<List<StorageVolume>> volumes() async =>
      drives ??
      [
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
  Future<StorageListing> browse(String path) async => StorageListing(
    entries: limited && !indexed ? [] : await list(path),
    accessLimited: limited,
  );
  @override
  Future<Uint8List?> thumbnail(String path) async => null;
}

class _Index extends MediaIndexNotifier {
  @override
  Future<List<VideoItem>> build() async => _videos;
  @override
  Future<void> refresh() async {}
}

class _MediaPermission extends MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
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
    Stream<Object?>? changes,
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
        mediaIndexProvider.overrideWith(_Index.new),
        mediaPermissionImplProvider.overrideWithValue(_MediaPermission()),
        mediaIndexerProvider.overrideWithValue(_Artwork()),
        storageBrowserProvider.overrideWithValue(storage ?? _Storage()),
        storageChangesProvider.overrideWith(
          (ref) => changes ?? const Stream.empty(),
        ),
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
          child: TvInputMode(enabled: true, child: screen),
        ),
      ),
      container: c,
      appBuilder: (_, child) => TvInputMode(enabled: true, child: child!),
      theme: KivoTheme.television().copyWith(
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
    'D-pad reaches the regular library and restores its focus after settings',
    (t) async {
      await pump(t, const TvLibraryScreen());
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tv-all-videos')), findsOneWidget);
      expect(find.byType(TvStorageScreen), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.byType(TvSettingsScreen), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tv-all-videos')), findsOneWidget);
    },
  );

  testWidgets(
    'a mounted drive opens in the normal streaming library and indexes automatically',
    (t) async {
      final storage = _Storage();
      await pump(t, const TvLibraryScreen(), storage: storage);
      expect(storage.rescans, 1);
      expect(find.byKey(const Key('tv-hero-play')), findsOneWidget);
      expect(find.byType(TvStorageScreen), findsNothing);
      expect(find.byIcon(Icons.usb), findsNothing);
    },
  );

  testWidgets(
    'the normal library waits for a drive and follows mounting without showing internal media',
    (t) async {
      final storage = _Storage()
        ..drives = [
          const StorageVolume(
            path: '/storage/emulated/0',
            name: 'Internal',
            removable: false,
          ),
        ];
      final changes = StreamController<Object?>();
      addTearDown(changes.close);
      await pump(
        t,
        const TvLibraryScreen(),
        storage: storage,
        changes: changes.stream,
      );
      expect(find.textContaining('Conecta tu memoria'), findsOneWidget);
      expect(find.byKey(const Key('tv-hero-play')), findsNothing);
      storage.drives = null;
      changes.add('android.intent.action.MEDIA_MOUNTED');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tv-hero-play')), findsOneWidget);
      expect(find.byType(TvStorageScreen), findsNothing);
    },
  );

  testWidgets(
    'resuming refreshes the source without switching out of the library',
    (t) async {
      await pump(t, const TvLibraryScreen());
      await t.tap(find.byKey(const Key('tv-complete-library')));
      await t.pumpAndSettle();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tv-all-videos')), findsOneWidget);
      expect(find.byType(TvStorageScreen), findsNothing);
    },
  );

  testWidgets('screen reader receives the seek value and toggle state', (
    t,
  ) async {
    await pump(t, const TvSettingsScreen());
    final interval = t
        .getSemantics(find.bySemanticsLabel('Salto con las flechas del mando'))
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

  testWidgets(
    'a filtered empty USB read offers access recovery instead of claiming no videos',
    (t) async {
      await pump(
        t,
        const TvStorageScreen(),
        storage: _Storage()..limited = true,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('No hay videos en esta carpeta'), findsNothing);
      expect(find.text('Permitir acceso al almacenamiento'), findsWidgets);
    },
  );

  testWidgets(
    'a limited empty folder asks Android to index videos before requesting full access',
    (t) async {
      final storage = _Storage()
        ..limited = true
        ..revealOnRescan = true;
      await pump(t, const TvStorageScreen(), storage: storage);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(storage.rescans, 1);
      expect(storage.limited, isTrue);
      expect(find.text('Películas'), findsOneWidget);
      expect(find.text('Android está limitando el acceso'), findsNothing);
      expect(find.text('No hay videos en esta carpeta'), findsNothing);
    },
  );

  testWidgets('TV seek interval can be changed entirely with a D-pad', (
    t,
  ) async {
    final c = await pump(t, const TvSettingsScreen());
    await capture(t, 'settings');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(TvOptionRow), findsWidgets);
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
    await t.tap(find.byKey(const Key('tv-complete-library')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tv-search-nav')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'bosque');
    await t.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is TvVideoCard && w.video.id == '7'),
      findsNothing,
    );
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is TvVideoCard && w.video.id == '7'),
      findsOneWidget,
    );
  });

  testWidgets(
    'complete library stays on TV and Back returns to the home library',
    (t) async {
      await pump(t, const TvLibraryScreen());
      final complete = find.byKey(const Key('tv-complete-library'));
      await t.ensureVisible(complete);
      await t.pumpAndSettle();
      await t.tap(complete);
      await t.pump();
      expect(
        find.byType(HomeShell),
        findsNothing,
        reason: 'A TV action must never enter the phone navigation shell',
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tv-all-videos')), findsOneWidget);
      await capture(t, 'catalog');
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tv-all-videos')), findsNothing);
      expect(find.byKey(const Key('tv-hero-play')), findsOneWidget);
    },
  );

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
