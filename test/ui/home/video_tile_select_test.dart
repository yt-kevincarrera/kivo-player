import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import '../../fakes/fakes.dart';

const _v = VideoItem(
  id: '1', uri: 'content://v/1', name: 'clip.mp4', folder: 'Movies',
  durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
);

Widget _host(SettingsService s, {required bool selected, required VoidCallback onLong}) {
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  return UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(width: 300, child: VideoTile(
        video: _v, listRow: false, selected: selected, selecting: true,
        onTap: (_) {}, onLongPress: onLong,
      )))),
    ),
  );
}

void main() {
  testWidgets('long-press fires onLongPress', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    var longPressed = false;
    await tester.pumpWidget(_host(s, selected: false, onLong: () => longPressed = true));
    await tester.longPress(find.byType(VideoTile));
    await tester.pump(const Duration(milliseconds: 400));
    expect(longPressed, true);
  });

  testWidgets('selected tile shows the check overlay', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await tester.pumpWidget(_host(s, selected: true, onLong: () {}));
    await tester.pump();
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
