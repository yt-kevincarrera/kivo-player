import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('VideoTile.onTap emits the thumbnail global rect', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
    ]);
    addTearDown(c.dispose);

    const video = VideoItem(
      id: '1',
      uri: 'content://v/1',
      name: 'clip.mp4',
      folder: 'f',
      durationMs: 1000,
      sizeBytes: 10,
      dateAddedMs: 0,
    );

    Rect? captured;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: VideoTile(
                video: video,
                listRow: false,
                onTap: (origin) => captured = origin,
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byType(VideoTile));
    await tester.pump(const Duration(milliseconds: 400)); // PressBounce settle
    expect(captured, isNotNull);
    expect(captured!.width, greaterThan(0));
    expect(captured!.height, greaterThan(0));
  });
}
