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
import 'player/open/video_source.dart';
import 'platform/android/android_frame_extractor.dart';
import 'platform/android/android_media_indexer.dart';
import 'platform/android/permission_handler_media_permission.dart';
import 'platform/frame_extractor_provider.dart';
import 'platform/media_indexer_provider.dart';
import 'platform/media_permission_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  final settingsBox = await Hive.openBox('settings');
  final resumeBox = await Hive.openBox('resume');

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
      frameExtractorProvider.overrideWithValue(AndroidFrameExtractor()),
      mediaIndexerProvider.overrideWithValue(AndroidMediaIndexer()),
      mediaPermissionImplProvider.overrideWithValue(PermissionHandlerMediaPermission()),
    ],
    child: const KivoApp(),
  ));
}
