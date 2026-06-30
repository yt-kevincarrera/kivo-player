import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/library_screen.dart';
import 'fakes/fakes.dart';

class _GrantedPerm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('LibraryScreen renders without crashing', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final resumeStore = InMemoryResumeStore();
    final engine = FakePlaybackEngine();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWithValue(s),
          mediaPermissionImplProvider.overrideWithValue(_GrantedPerm()),
          mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
          resumeServiceProvider.overrideWithValue(ResumeService(resumeStore)),
          playbackEngineProvider.overrideWithValue(engine),
          frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
  });
}
