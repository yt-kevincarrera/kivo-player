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
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/platform/television_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/queue/queue_undo.dart';
import 'package:kivo_player/player/tracks/track_delay_controller.dart';
import 'package:kivo_player/ui/player/keys/player_keys.dart';
import 'package:kivo_player/ui/player/state/queue_strip_state.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/player/tracks/track_sync_hud.dart';
import 'package:kivo_player/ui/tv/tv_input_mode.dart';
import 'package:kivo_player/ui/tv/tv_panel.dart';
import 'package:kivo_player/ui/tv/tv_player_controls.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

class _Artwork extends FakeMediaIndexer {
  static final images = <String, Uint8List>{};
  @override
  Future<Uint8List?> thumbnail(String id) async => images[id];
}

void main() {
  final captureKey = GlobalKey();
  setUpAll(() async {
    final fixtures = Platform.environment['KIVO_TV_FIXTURES'];
    if (fixtures != null) {
      for (final entry in {
        'a': 'mountain',
        'b': 'forest',
        'c': 'coast',
      }.entries) {
        _Artwork.images[entry.key] = await File(
          '$fixtures/${entry.value}.jpg',
        ).readAsBytes();
      }
    }
    final fonts = Platform.environment['KIVO_TV_FONT_DIR'];
    if (fonts != null) {
      for (final entry in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        await (FontLoader(entry.key)..addFont(
              File(
                '$fonts/${entry.value}',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  Future<void> capture(WidgetTester t, String name) async {
    final dir = Platform.environment['KIVO_TV_CAPTURE_DIR'];
    if (dir == null) return;
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  final l = l10nFor(const Locale('es'));
  Future<(ProviderContainer, FakePlaybackEngine)> pump(
    WidgetTester t, {
    double scale = 1,
  }) async {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final engine = FakePlaybackEngine();
    engine.audioTracksValue = const [
      MediaTrack(id: 'es', title: 'Español', language: 'es'),
      MediaTrack(id: 'en', title: 'English', language: 'en'),
    ];
    engine.currentAudioTrackValue = engine.audioTracksValue.first;
    engine.subtitleTracksValue = const [
      MediaTrack(id: 'sub-es', title: 'Español', language: 'es'),
    ];
    engine.currentSubtitleTrackValue = engine.subtitleTracksValue.first;
    addTearDown(engine.dispose);
    final settings = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(
      overrides: [
        isTelevisionProvider.overrideWithValue(true),
        settingsServiceProvider.overrideWithValue(settings),
        playbackEngineProvider.overrideWithValue(engine),
        bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
        mediaIndexerProvider.overrideWithValue(_Artwork()),
        mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()),
        subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
      ],
    );
    addTearDown(c.dispose);
    c
        .read(currentVideoProvider.notifier)
        .open(
          const VideoSession(
            playbackPath: '/videos/a.mkv',
            displayName: 'Entre montañas.mkv',
            queue: ['/videos/a.mkv', '/videos/b.mkv', '/videos/c.mkv'],
            queueNames: [
              'Entre montañas.mkv',
              'El bosque vivo.mp4',
              'Días junto al mar.avi',
            ],
            queueIds: ['a', 'b', 'c'],
            index: 0,
          ),
        );
    await pumpLocalized(
      t,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: TvInputMode(
            enabled: true,
            child: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  if (_Artwork.images['a'] != null)
                    Image.memory(_Artwork.images['a']!, fit: BoxFit.cover),
                  const TvPlayerControls(visible: true),
                  const TrackSyncHud(),
                ],
              ),
            ),
          ),
        ),
      ),
      container: c,
      appBuilder: (_, child) => TvInputMode(enabled: true, child: child!),
      captureKey: captureKey,
      theme: KivoTheme.television(),
    );
    if (_Artwork.images.isNotEmpty) {
      await t.runAsync(() async {
        for (final bytes in _Artwork.images.values) {
          await precacheImage(MemoryImage(bytes), captureKey.currentContext!);
        }
      });
    }
    await t.pumpAndSettle();
    return (c, engine);
  }

  Future<void> advanced(WidgetTester t) async {
    await t.tap(find.byKey(const Key('tv-player-more')));
    await t.pumpAndSettle();
    final row = find.text(l.tvMorePlayback).last;
    await t.ensureVisible(row);
    await t.tap(row);
    await t.pumpAndSettle();
  }

  testWidgets(
    'queue stays in playback; its editor removes and undoes without leaving',
    (t) async {
      final (c, _) = await pump(t);
      await capture(t, 'player-controls');
      expect(find.byKey(const Key('tv-queue-strip')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('tv-strip-/videos/b.mkv')));
      await t.pump();
      expect(c.read(queueJumpProvider), 1);
      await t.tap(find.text(l.tvEditQueue));
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('${l.tvOptions}: El bosque vivo.mp4'));
      await t.pumpAndSettle();
      await t.tap(find.text(l.playerQueueRemove));
      await t.pumpAndSettle();
      expect(c.read(currentVideoProvider)!.playOrder.length, 2);
      expect(c.read(queueUndoProvider), isNotNull);
      await t.tap(find.text(l.commonUndo));
      await t.pumpAndSettle();
      expect(c.read(currentVideoProvider)!.playOrder.length, 3);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tv-queue-strip')), findsOneWidget);
      c.read(controlsVisibleProvider.notifier).hide();
    },
  );

  testWidgets('D-pad selects an audio track and returns focus to playback', (
    t,
  ) async {
    final (c, engine) = await pump(t);
    c.read(playPauseFocusProvider).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    final invoker = FocusManager.instance.primaryFocus;
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(TvOptionRow), findsWidgets);
    await capture(t, 'player-audio');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(engine.currentAudioTrackId, 'en');
    expect(c.read(settingsProvider).preferredAudioLanguage, 'en');
    expect(invoker!.hasFocus, isTrue);
    c.read(controlsVisibleProvider.notifier).hide();
  });

  testWidgets('D-pad reaches subtitles and more past audio and returns left', (
    t,
  ) async {
    final (c, _) = await pump(t);
    c.read(playPauseFocusProvider).requestFocus();
    await t.pump();
    for (final key in [
      'tv-player-audio',
      'tv-player-subtitles',
      'tv-player-more',
    ]) {
      // From play: forward, audio, subtitles, more, all in the same row.
      if (key == 'tv-player-audio') {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
      }
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(
        t
            .getSemantics(find.byKey(Key(key)))
            .hasFlag(ui.SemanticsFlag.isFocused),
        isTrue,
        reason:
            '$key must have visible focus; '
            'audio=${t.getRect(find.byKey(const Key('tv-player-audio')))}; '
            'subtitles=${t.getRect(find.byKey(const Key('tv-player-subtitles')))}; '
            'more=${t.getRect(find.byKey(const Key('tv-player-more')))}; '
            'focused=${FocusManager.instance.primaryFocus}',
      );
    }
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.text(l.tvImage), findsOneWidget);
    await capture(t, 'player-more');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(
      t
          .getSemantics(find.byKey(const Key('tv-player-more')))
          .hasFlag(ui.SemanticsFlag.isFocused),
      isTrue,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(
      t
          .getSemantics(find.byKey(const Key('tv-player-subtitles')))
          .hasFlag(ui.SemanticsFlag.isFocused),
      isTrue,
    );
    c.read(controlsVisibleProvider.notifier).hide();
  });

  testWidgets(
    'TV advanced playback retains repeat, shuffle, loop, decoder and end actions',
    (t) async {
      await pump(t);
      await advanced(t);
      await t.tap(find.text(l.playerMenuGroupPlayback).last);
      await t.pumpAndSettle();
      for (final label in [
        l.playerMenuRepeat,
        l.playerMenuShuffle,
        l.playerMenuAbLoop,
        l.endActionsTitle,
      ]) {
        expect(find.text(label), findsWidgets);
      }
      final end = find.text(l.endActionsTitle).last;
      await t.ensureVisible(end);
      await t.tap(end);
      await t.pumpAndSettle();
      expect(find.text(l.endActionsTitle), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'large text keeps every player action visible and the right edge retains focus',
    (t) async {
      final (c, _) = await pump(t, scale: 2);
      c.read(playPauseFocusProvider).requestFocus();
      await t.pump();
      for (var i = 0; i < 8; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
      }
      final more = find.byKey(const Key('tv-player-more'));
      expect(t.getSemantics(more).hasFlag(ui.SemanticsFlag.isFocused), isTrue);
      final rect = t.getRect(more);
      expect(rect.left, greaterThanOrEqualTo(44));
      expect(rect.right, lessThanOrEqualTo(1236));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();
      expect(
        t
            .getSemantics(find.byKey(const Key('tv-player-subtitles')))
            .hasFlag(ui.SemanticsFlag.isFocused),
        isTrue,
      );
      expect(t.takeException(), isNull);
      c.read(controlsVisibleProvider.notifier).hide();
    },
  );

  testWidgets(
    'subtitle appearance uses TV choices and a remote-adjustable value',
    (t) async {
      final (c, _) = await pump(t);
      await t.tap(find.byKey(const Key('tv-player-subtitles')));
      await t.pumpAndSettle();
      await t.tap(find.text(l.tvSubtitleSettings));
      await t.pumpAndSettle();
      await t.tap(find.text(l.playerTracksStyleTabLabel));
      await t.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-panel-back');
      await capture(t, 'player-subtitle-style');
      expect(
        find.ancestor(
          of: find.text(l.playerTracksSizeLabel),
          matching: find.byType(TvOptionRow),
        ),
        findsOneWidget,
      );
      final initial = c.read(settingsProvider).subtitleFontSize;
      await t.tap(find.text(l.playerTracksSizeLabel));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(c.read(settingsProvider).subtitleFontSize, initial + 1);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text(l.playerTracksSizeLabel), findsOneWidget);
      expect(t.takeException(), isNull);
      c.read(controlsVisibleProvider.notifier).hide();
    },
  );

  testWidgets('synchronization remains reachable in a TV menu', (t) async {
    final (c, _) = await pump(t);
    await advanced(t);
    final sync = find.text(l.playerMenuSync).last;
    await t.ensureVisible(sync);
    await t.tap(sync);
    await t.pumpAndSettle();
    expect(c.read(syncHudProvider), SyncTarget.subtitles);
  });

  testWidgets(
    'TV sync adjusts and resets without timing out while using the remote',
    (t) async {
      final (c, _) = await pump(t);
      c.read(syncHudProvider.notifier).show(SyncTarget.audio);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tv-sync-plus')));
      await t.pump(const Duration(milliseconds: 150));
      expect(c.read(audioSyncProvider), 50);
      await t.pump(const Duration(seconds: 9));
      expect(c.read(syncHudProvider), SyncTarget.audio);
      await t.tap(find.byKey(const Key('tv-sync-reset')));
      await t.pump(const Duration(milliseconds: 150));
      expect(c.read(audioSyncProvider), 0);
      await capture(t, 'player-sync');
      await t.tap(find.text(l.commonGoBack).last);
      await t.pumpAndSettle();
      expect(c.read(syncHudProvider), isNull);
      c.read(controlsVisibleProvider.notifier).hide();
    },
  );

  testWidgets('TV queue and controls fit at twice the system text size', (
    t,
  ) async {
    await pump(t, scale: 2);
    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('tv-queue-strip')), findsOneWidget);
  });
}
