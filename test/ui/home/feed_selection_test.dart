import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/video_density_feed.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import '../../fakes/fakes.dart';

const _a = VideoItem(id: '1', uri: 'u1', name: 'a.mp4', folder: 'F', durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);
const _b = VideoItem(id: '2', uri: 'u2', name: 'b.mp4', folder: 'F', durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);

void main() {
  testWidgets('long-press enters selection; tap then toggles instead of opening', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    ]);
    addTearDown(c.dispose);
    var opens = 0;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: VideoDensityFeed(
        videos: const [_a, _b], groupByDate: false, showContinueRow: false,
        onOpen: (_, __, ___) => opens++,
      ))),
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(VideoTile).first);
    await tester.pumpAndSettle();
    expect(c.read(librarySelectionProvider), {'u1'});

    // Now a tap toggles, does not open.
    await tester.tap(find.byType(VideoTile).at(1));
    await tester.pumpAndSettle();
    expect(c.read(librarySelectionProvider), {'u1', 'u2'});
    expect(opens, 0);
  });
}
