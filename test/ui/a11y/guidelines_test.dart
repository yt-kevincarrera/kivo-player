import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import '../player/player_screen_controls_test.dart' show NoopControls;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/ui/home/home_shell.dart';
import 'package:kivo_player/ui/vault/pin_pad.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

class _Granted implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

VideoItem _v(String n, String f) => VideoItem(
  id: n,
  uri: 'content://$n',
  name: '$n.mp4',
  folder: f,
  durationMs: 600000,
  sizeBytes: 1000000,
  dateAddedMs: 0,
);

/// Every tappable thing has something for TalkBack to say, and text is
/// readable against what it sits on. (Touch-target size is not asserted
/// screen-wide: the library's filter chips and the player's time label are
/// smaller than 48 dp by design, and TalkBack users reach them by swiping.)
Future<void> _check(WidgetTester t) async {
  await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(t, meetsGuideline(textContrastGuideline));
}

void main() {
  testWidgets('library (videos, folders) and settings', (t) async {
    final h = t.ensureSemantics();
    for (final ch in [
      'receive_sharing_intent/messages',
      'receive_sharing_intent/events-media',
    ]) {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(ch),
        (_) async => null,
      );
    }
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        mediaPermissionImplProvider.overrideWithValue(_Granted()),
        mediaIndexerProvider.overrideWithValue(
          FakeMediaIndexer([
            _v('a', 'Movies'),
            _v('b', 'Movies'),
            _v('c', 'Series'),
          ]),
        ),
        playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
        bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
        resumeServiceProvider.overrideWithValue(
          ResumeService(InMemoryResumeStore()),
        ),
        frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      ],
    );
    addTearDown(c.dispose);
    await pumpLocalized(
      t,
      const HomeShell(),
      theme: KivoTheme.dark(),
      container: c,
    );
    await t.pumpAndSettle();
    await _check(t);
    await t.tap(find.text('Carpetas'));
    await t.pumpAndSettle();
    await _check(t);
    await t.tap(find.text('Ajustes'));
    await t.pumpAndSettle();
    await _check(t);
    h.dispose();
  });

  testWidgets('player with the controls up', (t) async {
    final h = t.ensureSemantics();
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(gestureMapShown: true));
    final c = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        playbackEngineProvider.overrideWithValue(engine),
        deviceControlsProvider.overrideWithValue(NoopControls()),
        resumeServiceProvider.overrideWithValue(
          ResumeService(InMemoryResumeStore()),
        ),
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
            playbackPath: '/v/ep1.mkv',
            displayName: 'ep1.mkv',
            queue: ['/v/ep1.mkv'],
            index: 0,
          ),
        );
    await pumpLocalized(t, const PlayerScreen(), container: c);
    await t.pump();
    await t.tapAt(t.getCenter(find.byType(PlayerScreen)));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 400));
    await _check(t);
    await t.pump(const Duration(seconds: 4));
    h.dispose();
  });

  testWidgets('vault PIN pad', (t) async {
    final h = t.ensureSemantics();
    await pumpLocalized(
      t,
      Scaffold(
        body: PinPad(title: 'PIN', onComplete: (_) {}),
      ),
      theme: KivoTheme.dark(),
    );
    await t.pumpAndSettle();
    await _check(t);
    h.dispose();
  });
}
