import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'core/settings/settings_store.dart';
import 'core/settings/settings_service.dart';
import 'core/settings/settings_provider.dart';
import 'player/engine/media_kit_engine.dart';
import 'player/engine/playback_provider.dart';
import 'player/resume/resume_store.dart';
import 'player/resume/resume_service.dart';
import 'player/library/played.dart';
import 'player/open/video_source.dart';
import 'platform/all_files_access_provider.dart';
import 'platform/android/android_all_files_access.dart';
import 'platform/android/android_frame_extractor.dart';
import 'platform/android/android_media_file_ops.dart';
import 'platform/android/android_media_indexer.dart';
import 'platform/android/android_media_session.dart';
import 'platform/android/android_pip_controller.dart';
import 'platform/android/android_subtitle_finder.dart';
import 'platform/android/permission_handler_media_permission.dart';
import 'platform/frame_extractor_provider.dart';
import 'platform/media_file_ops_provider.dart';
import 'platform/media_indexer_provider.dart';
import 'platform/media_permission_provider.dart';
import 'platform/media_session_provider.dart';
import 'platform/pip_controller_provider.dart';
import 'platform/subtitle_finder_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  final settingsBox = await Hive.openBox('settings');
  final resumeBox = await Hive.openBox('resume');
  final playedBox = await Hive.openBox('played');

  final settingsService = await SettingsService.load(HiveSettingsStore(settingsBox));
  final resumeService = ResumeService(
    HiveResumeStore(resumeBox),
    minSeconds: settingsService.current.resumeMinSeconds,
  );
  final engine = MediaKitEngine();

  runApp(ProviderScope(
    overrides: [
      settingsServiceProvider.overrideWithValue(settingsService),
      playbackEngineProvider.overrideWithValue(engine),
      resumeServiceProvider.overrideWithValue(resumeService),
      playedStoreProvider.overrideWithValue(HivePlayedStore(playedBox)),
      frameExtractorProvider.overrideWithValue(AndroidFrameExtractor()),
      mediaIndexerProvider.overrideWithValue(AndroidMediaIndexer()),
      mediaFileOpsProvider.overrideWithValue(AndroidMediaFileOps()),
      mediaPermissionImplProvider.overrideWithValue(PermissionHandlerMediaPermission()),
      subtitleFinderProvider.overrideWithValue(AndroidSubtitleFinder()),
      mediaSessionProvider.overrideWithValue(AndroidMediaSessionBridge()),
      pipControllerProvider.overrideWithValue(AndroidPipController()),
      allFilesAccessProvider.overrideWithValue(AndroidAllFilesAccess()),
    ],
    child: const KivoApp(),
  ));
}
