import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import '../../fakes/fakes.dart';

const _video = VideoItem(
  id: '1',
  uri: 'content://1',
  name: 'cool.mkv',
  folder: 'F',
  durationMs: 65000,
  sizeBytes: 51380224, // ~49 MB
  dateAddedMs: 0,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
    ],
    child: MaterialApp(
      theme: KivoTheme.light(),
      home: Scaffold(body: Center(child: SizedBox(width: 300, child: child))),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('list-row mode: shows title, size, duration, fires onTap via title tap', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      VideoTile(
        video: _video,
        listRow: true,
        sizeLabel: '49.00 MB',
        progress: 0.5,
        onTap: () => tapped = true,
      ),
    );

    expect(find.text('cool.mkv'), findsOneWidget);
    expect(find.text('49.00 MB'), findsOneWidget);
    expect(find.text('01:05'), findsOneWidget);

    // Tap the TITLE text — proves the whole row is tappable, not just the thumbnail.
    await tester.tap(find.text('cool.mkv'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('cover mode: shows title, duration, fires onTap', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      VideoTile(
        video: _video,
        listRow: false,
        progress: 0.5,
        onTap: () => tapped = true,
      ),
    );

    expect(find.text('cool.mkv'), findsOneWidget);
    expect(find.text('01:05'), findsOneWidget);

    await tester.tap(find.byType(VideoTile));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('cover mode: no sizeLabel shown', (tester) async {
    await _pump(
      tester,
      VideoTile(
        video: _video,
        listRow: false,
        sizeLabel: '49.00 MB',
        onTap: () {},
      ),
    );

    // sizeLabel is passed but cover layout does not render it
    expect(find.text('49.00 MB'), findsNothing);
  });
}
