import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/selection_bottom_bar.dart';
import 'package:kivo_player/ui/home/widgets/video_options_sheet.dart';
import '../../fakes/fakes.dart';

const _a = VideoItem(
    id: '1', uri: 'u1', name: 'a.mp4', folder: 'F',
    durationMs: 1, sizeBytes: 1, dateAddedMs: 0);

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('the selection bar offers adding to a playlist', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    var tick = 0;
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([_a])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      playlistStoreProvider.overrideWithValue(InMemoryPlaylistStore()),
      playlistClockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    c.read(librarySelectionProvider.notifier).selectAll(['u1']);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(bottomNavigationBar: SelectionBottomBar()),
      ),
    ));
    await tester.pumpAndSettle();

    // Only that the entry point exists and is reachable — the sheet itself is
    // covered by its own test.
    expect(find.text('A una lista'), findsOneWidget);
  });

  testWidgets('the video ⋮ sheet offers adding to a playlist', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (ctx, ref, _) => Builder(
                builder: (b) => TextButton(
                  onPressed: () => showVideoOptions(b, ref, _a),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Añadir a lista'), findsOneWidget);
  });
}
