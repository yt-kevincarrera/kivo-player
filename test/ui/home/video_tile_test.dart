import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('tile shows title, duration, and fires onTap', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    var tapped = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      ],
      child: MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 200, child: VideoTile(
        video: const VideoItem(id: '1', uri: 'content://1', name: 'cool.mkv', folder: 'F',
            durationMs: 65000, sizeBytes: 1, dateAddedMs: 0),
        progress: 0.5, onTap: () => tapped = true))))),
    ));
    await tester.pump();
    expect(find.text('cool.mkv'), findsOneWidget);
    expect(find.text('01:05'), findsOneWidget);
    await tester.tap(find.byType(VideoTile));
    expect(tapped, isTrue);
  });
}
