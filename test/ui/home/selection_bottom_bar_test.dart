import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/selection_bottom_bar.dart';
import '../../fakes/fakes.dart';

const _a = VideoItem(id: '1', uri: 'u1', name: 'a.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 0);
const _b = VideoItem(id: '2', uri: 'u2', name: 'b.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 0);

class _Perm implements MediaPermission {
  @override Future<MediaAccess> status() async => MediaAccess.granted;
  @override Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('bottom bar shares the selected videos resolved from the index', (tester) async {
    final ops = FakeMediaFileOps();
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaFileOpsProvider.overrideWithValue(ops),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([_a, _b])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    ]);
    addTearDown(c.dispose);
    // Prime the index + a selection.
    await c.read(mediaIndexProvider.future);
    c.read(librarySelectionProvider.notifier).selectAll(['u1']);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(bottomNavigationBar: SelectionBottomBar())),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.share));
    await tester.pump();
    expect(ops.sharedManyUris.single, ['u1']);
  });
}
