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
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/folder_screen.dart';
import '../../fakes/fakes.dart';

class _GrantedPerm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

const _snapshot = [
  VideoItem(
    id: '1',
    uri: 'content://1',
    name: 'Stale.mp4',
    folder: 'Movies',
    durationMs: 90000,
    sizeBytes: 1,
    dateAddedMs: 1,
  ),
];

// The live index no longer has the "Stale.mp4" (simulating it having been
// deleted/renamed away) but has a fresh "Fresh.mp4" in the same folder, plus
// one in a different folder that must not leak in.
const _indexed = [
  VideoItem(
    id: '2',
    uri: 'content://2',
    name: 'Fresh.mp4',
    folder: 'Movies',
    durationMs: 90000,
    sizeBytes: 1,
    dateAddedMs: 2,
  ),
  VideoItem(
    id: '3',
    uri: 'content://3',
    name: 'Other.mp4',
    folder: 'Other',
    durationMs: 90000,
    sizeBytes: 1,
    dateAddedMs: 3,
  ),
];

Future<void> _pump(WidgetTester tester, {List<VideoItem> videos = const []}) async {
  final settingsService = await SettingsService.load(InMemorySettingsStore());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(settingsService),
        mediaPermissionImplProvider.overrideWithValue(_GrantedPerm()),
        mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(_indexed)),
        resumeServiceProvider.overrideWithValue(
          ResumeService(InMemoryResumeStore()),
        ),
        frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
        playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      ],
      child: MaterialApp(
        theme: KivoTheme.light(),
        home: FolderScreen(folder: 'Movies', videos: videos),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'FolderScreen shows tiles derived live from the index, not the frozen snapshot',
      (tester) async {
    await _pump(tester, videos: _snapshot);

    // The stale snapshot tile is gone (as if deleted/renamed elsewhere)...
    expect(find.text('Stale.mp4'), findsNothing);
    // ...while the live index's matching-folder video shows up...
    expect(find.text('Fresh.mp4'), findsOneWidget);
    // ...and a video from a different folder does not leak in.
    expect(find.text('Other.mp4'), findsNothing);
  });
}
