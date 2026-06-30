import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/player/seek/seek_preview.dart';
import 'package:kivo_player/ui/player/seek/seek_preview_bubble.dart';
import '../../../fakes/fakes.dart';

void main() {
  testWidgets('bubble hidden when not scrubbing, shown with timestamp when scrubbing',
      (tester) async {
    final settings = await SettingsService.load(InMemorySettingsStore());
    final engine = FakePlaybackEngine();
    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(settings),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SeekPreviewBubble())),
    ));
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining(':'), findsNothing);

    container.read(scrubProvider.notifier).state = const Duration(seconds: 75);
    await tester.pump();
    expect(find.text('01:15'), findsOneWidget); // timestamp shown
  });
}
