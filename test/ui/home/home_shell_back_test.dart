import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/home_shell.dart';
import 'package:kivo_player/ui/home/library_screen.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

const _a = VideoItem(
    id: '1',
    uri: 'u1',
    name: 'a.mp4',
    folder: 'F',
    durationMs: 1,
    sizeBytes: 1,
    dateAddedMs: 0);

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

Future<ProviderContainer> _mount(WidgetTester tester) async {
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
  await pumpLocalized(
    tester,
    const HomeShell(),
    theme: KivoTheme.dark(),
    container: c,
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('system back from Carpetas returns to Todo instead of leaving',
      (tester) async {
    final c = await _mount(tester);

    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    expect(c.read(librarySubTabProvider), 1);

    // The system back gesture, as the platform delivers it.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue, reason: 'the shell must claim the back, not the OS');
    expect(c.read(librarySubTabProvider), 0);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('system back from Listas returns to Todo instead of leaving',
      (tester) async {
    final c = await _mount(tester);

    await tester.tap(find.byIcon(Icons.queue_music_outlined));
    await tester.pumpAndSettle();
    expect(c.read(librarySubTabProvider), 2);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(c.read(librarySubTabProvider), 0);
  });
}
