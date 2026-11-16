import 'package:flutter/material.dart';
import 'dart:ui' show SemanticsFlag;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/platform/television_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/tv/tv_input_mode.dart';
import 'package:kivo_player/ui/tv/tv_player_controls.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';
import '../player/player_screen_controls_test.dart' show NoopControls;

class _TvControls extends NoopControls {
  final orientations = <List<DeviceOrientationLock>>[];
  @override
  Future<void> setOrientation(List<DeviceOrientationLock> value) async =>
      orientations.add(value);
}

void main() {
  testWidgets(
    'TV opens landscape without gesture tutorial; Back hides controls then returns',
    (t) async {
      t.view.physicalSize = const Size(1280, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final engine = FakePlaybackEngine();
      addTearDown(engine.dispose);
      final settings = await SettingsService.load(InMemorySettingsStore());
      final device = _TvControls();
      final store = InMemoryResumeStore();
      final c = ProviderContainer(
        overrides: [
          isTelevisionProvider.overrideWithValue(true),
          settingsServiceProvider.overrideWithValue(settings),
          playbackEngineProvider.overrideWithValue(engine),
          deviceControlsProvider.overrideWithValue(device),
          resumeServiceProvider.overrideWithValue(ResumeService(store)),
          playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
          bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
          frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
          subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
          pipControllerProvider.overrideWithValue(FakePipController()),
        ],
      );
      addTearDown(c.dispose);
      c
          .read(currentVideoProvider.notifier)
          .open(
            const VideoSession(
              playbackPath: '/v/film.mkv',
              displayName: 'film.mkv',
              queue: ['/v/film.mkv'],
              index: 0,
            ),
          );
      await pumpLocalized(
        t,
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const TvInputMode(enabled: true, child: PlayerScreen()),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
        container: c,
      );
      await t.tap(find.text('Open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(device.orientations.first, [DeviceOrientationLock.landscape]);
      expect(
        device.orientations.expand((e) => e),
        isNot(contains(DeviceOrientationLock.portrait)),
      );
      expect(c.read(settingsProvider).gestureMapShown, false);
      expect(find.byType(TvPlayerControls), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect(c.read(controlsVisibleProvider), true);
      await t.pump();
      for (var i = 0; i < 4; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump(const Duration(milliseconds: 250));
      }
      expect(
        t
            .getSemantics(find.byKey(const Key('tv-player-more')))
            .hasFlag(SemanticsFlag.isFocused),
        isTrue,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 250));
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 250));
      expect(
        t
            .getSemantics(find.byKey(const Key('tv-player-more')))
            .hasFlag(SemanticsFlag.isFocused),
        isTrue,
      );
      await t.binding.handlePopRoute();
      await t.pump();
      expect(c.read(controlsVisibleProvider), false);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(engine.lastPlayingCommand, false);
      await t.pump(const Duration(seconds: 5));
    },
  );
}
