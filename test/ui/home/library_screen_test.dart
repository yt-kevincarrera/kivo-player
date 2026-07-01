import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/ui/home/library_screen.dart';
import '../../fakes/fakes.dart';

class _GrantedPerm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

/// A fixed timestamp so groupByDay produces a predictable label.
/// The videos are created with dateAddedMs = 1 (1970-01-01), which will
/// produce a "1 ene" section header relative to any near-modern "now".
final _videos = [
  const VideoItem(
    id: '1',
    uri: 'content://1',
    name: 'Inception.mp4',
    folder: 'Movies',
    durationMs: 90000,
    sizeBytes: 1,
    dateAddedMs: 1,
  ),
  const VideoItem(
    id: '2',
    uri: 'content://2',
    name: 'Avatar.mp4',
    folder: 'Downloads',
    durationMs: 120000,
    sizeBytes: 1,
    dateAddedMs: 1,
  ),
];

Future<ProviderScope> _buildApp(WidgetTester tester) async {
  final settingsService = await SettingsService.load(InMemorySettingsStore());
  final fake = FakeMediaIndexer(_videos);
  final resumeStore = InMemoryResumeStore();
  final engine = FakePlaybackEngine();

  final scope = ProviderScope(
    overrides: [
      settingsServiceProvider.overrideWithValue(settingsService),
      mediaPermissionImplProvider.overrideWithValue(_GrantedPerm()),
      mediaIndexerProvider.overrideWithValue(fake),
      resumeServiceProvider.overrideWithValue(ResumeService(resumeStore)),
      playbackEngineProvider.overrideWithValue(engine),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    ],
    child: MaterialApp(
      theme: KivoTheme.light(),
      home: const LibraryScreen(),
    ),
  );
  await tester.pumpWidget(scope);
  await tester.pumpAndSettle();
  return scope;
}

void main() {
  testWidgets('Kivo wordmark is shown in the AppBar', (tester) async {
    await _buildApp(tester);

    expect(find.text('Kivo'), findsOneWidget);
  });

  testWidgets('Todo chip is shown', (tester) async {
    await _buildApp(tester);

    expect(find.text('Todo'), findsOneWidget);
  });

  testWidgets('Todo tab shows known video name under a date section header',
      (tester) async {
    await _buildApp(tester);

    // The default tab is Todo (index 0). At least one video name must appear.
    expect(find.text('Inception.mp4'), findsOneWidget);
    expect(find.text('Avatar.mp4'), findsOneWidget);
  });

  testWidgets('Tapping Carpetas tab shows folder names', (tester) async {
    await _buildApp(tester);

    // Tap the "Carpetas" filter chip
    await tester.tap(find.text('Carpetas'));
    await tester.pumpAndSettle();

    // Both folder names should appear as folder cards
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
  });

  testWidgets('Todo tab is shown by default (video names visible)',
      (tester) async {
    await _buildApp(tester);

    // In Todo tab the video names should be visible.
    expect(find.text('Inception.mp4'), findsOneWidget);
  });

  testWidgets('Switching back from Carpetas to Todo restores video list',
      (tester) async {
    await _buildApp(tester);

    await tester.tap(find.text('Carpetas'));
    await tester.pumpAndSettle();
    expect(find.text('Movies'), findsOneWidget);

    await tester.tap(find.text('Todo'));
    await tester.pumpAndSettle();
    expect(find.text('Inception.mp4'), findsOneWidget);
  });

  testWidgets('tapping search shows a text field and hides the title',
      (tester) async {
    await _buildApp(tester);
    expect(find.text('Kivo'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();

    expect(find.text('Kivo'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typing a query filters to matching videos', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump();

    expect(find.text('Inception.mp4'), findsOneWidget);
    expect(find.text('Avatar.mp4'), findsNothing);
  });

  testWidgets('search matches by folder name too', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'downloads');
    await tester.pump();

    expect(find.text('Avatar.mp4'), findsOneWidget);
    expect(find.text('Inception.mp4'), findsNothing);
  });

  testWidgets('closing search restores the title and clears the query',
      (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('Kivo'), findsOneWidget);
    expect(find.text('Inception.mp4'), findsOneWidget);
    expect(find.text('Avatar.mp4'), findsOneWidget);
  });

  testWidgets('no search matches shows the empty message', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pump();

    expect(find.text('No se encontraron videos para "zzz-no-match"'), findsOneWidget);
  });

  testWidgets('sort menu changes order to alphabetical', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nombre A-Z'));
    await tester.pumpAndSettle();

    final avatarCenter = tester.getCenter(find.text('Avatar.mp4'));
    final inceptionCenter = tester.getCenter(find.text('Inception.mp4'));
    expect(avatarCenter.dy, lessThan(inceptionCenter.dy));
  });

  testWidgets('"No vistos" chip is hidden on the Carpetas tab', (tester) async {
    await _buildApp(tester);
    expect(find.text('No vistos'), findsOneWidget);

    await tester.tap(find.text('Carpetas'));
    await tester.pumpAndSettle();

    expect(find.text('No vistos'), findsNothing);
  });
}
