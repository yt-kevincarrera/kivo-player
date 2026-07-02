import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/background/audio_only.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/audio_only/audio_only_view.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import '../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;

  Future<void> pumpView(WidgetTester tester) async {
    engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: AudioOnlyView())),
    ));
    await tester.pump();
  }

  testWidgets('hidden when audio-only is off; black surface + title when on', (tester) async {
    await pumpView(tester);
    expect(find.text('SOLO AUDIO'), findsNothing);
    c.read(audioOnlyProvider.notifier).toggle();
    c.read(controlsVisibleProvider.notifier).show();
    await tester.pump();
    expect(find.text('SOLO AUDIO'), findsOneWidget);
    expect(find.text('ep1.mkv'), findsOneWidget);
    expect(engine.videoTrackEnabled, false);
    // Drain the controls auto-hide timer.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('toggling off restores the video track and hides the view', (tester) async {
    await pumpView(tester);
    c.read(audioOnlyProvider.notifier).toggle();
    await tester.pump();
    c.read(audioOnlyProvider.notifier).toggle();
    await tester.pump();
    expect(find.text('SOLO AUDIO'), findsNothing);
    expect(engine.videoTrackEnabled, true);
  });
}
