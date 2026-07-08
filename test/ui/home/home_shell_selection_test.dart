import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/ui/home/home_shell.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/selection_bottom_bar.dart';
import '../../fakes/fakes.dart';

const _a = VideoItem(id: '1', uri: 'u1', name: 'a.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 0);

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('HomeShell shows the bottom action bar when selection is active', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([_a])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: KivoTheme.dark(), home: const HomeShell()),
    ));
    await tester.pump();

    expect(find.byType(SelectionBottomBar), findsNothing);

    c.read(librarySelectionProvider.notifier).selectAll(['u1']);
    await tester.pump();

    expect(find.byType(SelectionBottomBar), findsOneWidget);
  });

  testWidgets('system back during selection clears it instead of popping the shell', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([_a])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: KivoTheme.dark(), home: const HomeShell()),
    ));
    await tester.pump();

    c.read(librarySelectionProvider.notifier).selectAll(['u1']);
    await tester.pump();
    expect(c.read(librarySelectionProvider), isNotEmpty);

    // Simulate the system back gesture (reaches the root PopScope).
    final handled = await tester.binding.handlePopRoute();
    await tester.pump();

    expect(handled, true); // consumed, not propagated to the OS (no shell pop)
    expect(c.read(librarySelectionProvider), isEmpty); // selection cleared
    expect(find.byType(HomeShell), findsOneWidget); // shell still there (no black screen)
    expect(find.byType(SelectionBottomBar), findsNothing);
  });
}
