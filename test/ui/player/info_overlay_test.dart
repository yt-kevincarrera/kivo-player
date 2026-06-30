import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/controls/info_overlay.dart';
import '../../fakes/fakes.dart';

void main() {
  test('infoOverlayText formats name + time', () {
    expect(
      infoOverlayText('name_time', 'ep1.mkv', const Duration(seconds: 65), const Duration(minutes: 10)),
      'ep1.mkv   01:05 / 10:00',
    );
    expect(infoOverlayText('name', 'ep1.mkv', Duration.zero, Duration.zero), 'ep1.mkv');
  });

  testWidgets('InfoOverlay hidden when showInfoOverlay is false', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final store = InMemorySettingsStore();
    await store.write(KivoSettings.defaults().copyWith(showInfoOverlay: false).toMap());
    final s = await SettingsService.load(store);
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
        const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: InfoOverlay())),
    ));
    expect(find.textContaining('ep1.mkv'), findsNothing);
  });
}
