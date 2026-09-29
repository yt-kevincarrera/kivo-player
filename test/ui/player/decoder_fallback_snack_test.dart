import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';
import 'video_ready_test.dart' show NoopControls;

void main() {
  testWidgets('a hardware open failure plays in software and offers Deshacer',
      (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    var attempts = 0;
    engine.openHook = (_) {
      if (++attempts == 1) throw StateError('mediacodec init');
    };
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(gestureMapShown: true));
    final prefs = InMemoryTrackPrefsStore();
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider
          .overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
      pipControllerProvider.overrideWithValue(FakePipController()),
      trackPrefsStoreProvider.overrideWithValue(prefs),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/ep1.mkv',
        displayName: 'ep1.mkv',
        queue: ['/v/ep1.mkv'],
        index: 0));

    await pumpLocalized(tester, const PlayerScreen(), container: c);
    await tester.pump();
    await tester.pump();

    final l10n = l10nFor(const Locale('es'));
    expect(find.text(l10n.playerDecoderFallbackSnack), findsOneWidget);
    expect(engine.openedPath, '/v/ep1.mkv');
    expect(prefs.forKey('ep1.mkv')!.decoder, 'sw');

    await tester.pump(const Duration(milliseconds: 600)); // slide-in
    await tester.tap(find.text(l10n.commonUndo));
    await tester.pump();
    expect(prefs.forKey('ep1.mkv')!.decoder, 'hw');
    expect(engine.hwdecWrites.last, 'auto-safe');

    await tester.pump(const Duration(seconds: 6)); // drain timers
  });
}
