import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'core/errors/error_log.dart';
import 'core/errors/error_log_provider.dart';
import 'core/settings/settings_store.dart';
import 'core/settings/settings_service.dart';
import 'core/settings/settings_provider.dart';
import 'player/engine/media_kit_engine.dart';
import 'player/engine/playback_provider.dart';
import 'player/resume/resume_store.dart';
import 'player/resume/resume_service.dart';
import 'player/tracks/subtitle_importer.dart';
import 'player/tracks/subtitle_prefs_store.dart';
import 'player/library/played.dart';
import 'player/open/video_source.dart';
import 'platform/all_files_access_provider.dart';
import 'platform/android/android_all_files_access.dart';
import 'platform/android/android_app_installer.dart';
import 'platform/android/android_frame_extractor.dart';
import 'platform/android/android_media_file_ops.dart';
import 'platform/android/android_media_indexer.dart';
import 'platform/android/android_media_session.dart';
import 'platform/android/android_pip_controller.dart';
import 'platform/android/android_subtitle_finder.dart';
import 'platform/android/local_auth_biometric.dart';
import 'platform/android/permission_handler_media_permission.dart';
import 'platform/app_installer_provider.dart';
import 'platform/biometric_auth_provider.dart';
import 'platform/frame_extractor_provider.dart';
import 'platform/media_file_ops_provider.dart';
import 'platform/media_indexer_provider.dart';
import 'platform/media_permission_provider.dart';
import 'platform/media_session_provider.dart';
import 'platform/pip_controller_provider.dart';
import 'platform/subtitle_finder_provider.dart';
import 'platform/vault_ops_provider.dart';
import 'platform/android/android_vault_ops.dart';
import 'vault/vault_store.dart';
import 'vault/vault_auth.dart';
import 'vault/vault_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  final settingsBox = await Hive.openBox('settings');
  final resumeBox = await Hive.openBox('resume');
  final playedBox = await Hive.openBox('played');
  final vaultBox = await Hive.openBox('vault');
  final vaultCredsBox = await Hive.openBox('vaultCreds');
  final errorsBox = await Hive.openBox('errors');
  final subtitlePrefsBox = await Hive.openBox('subtitlePrefs');

  // The app version and API level are captured once and stamped on every
  // recorded failure: a reported code is only useful with the device it came
  // from.
  final installer = AndroidAppInstaller();
  final errorLog = ErrorLog(
    HiveErrorLogStore(errorsBox),
    appVersion: await installer.appVersion(),
    androidSdk: await installer.androidSdk(),
  );

  final settingsService = await SettingsService.load(HiveSettingsStore(settingsBox));
  final resumeService = ResumeService(
    HiveResumeStore(resumeBox),
    minSeconds: settingsService.current.resumeMinSeconds,
  );
  final engine = MediaKitEngine();
  final subsDir = Directory('${(await getExternalStorageDirectory())!.path}/subs');

  runApp(ProviderScope(
    overrides: [
      settingsServiceProvider.overrideWithValue(settingsService),
      playbackEngineProvider.overrideWithValue(engine),
      resumeServiceProvider.overrideWithValue(resumeService),
      playedStoreProvider.overrideWithValue(HivePlayedStore(playedBox)),
      frameExtractorProvider.overrideWithValue(AndroidFrameExtractor()),
      mediaIndexerProvider.overrideWithValue(AndroidMediaIndexer(errorLog)),
      mediaFileOpsProvider.overrideWithValue(AndroidMediaFileOps(errorLog)),
      mediaPermissionImplProvider
          .overrideWithValue(PermissionHandlerMediaPermission(errorLog)),
      subtitleFinderProvider.overrideWithValue(AndroidSubtitleFinder()),
      mediaSessionProvider.overrideWithValue(AndroidMediaSessionBridge()),
      pipControllerProvider.overrideWithValue(AndroidPipController()),
      allFilesAccessProvider.overrideWithValue(AndroidAllFilesAccess()),
      errorLogProvider.overrideWithValue(errorLog),
      subtitlePrefsStoreProvider
          .overrideWithValue(HiveSubtitlePrefsStore(subtitlePrefsBox)),
      subtitleImporterProvider
          .overrideWithValue(FileSubtitleImporter(subsDir, log: errorLog)),
      appInstallerProvider.overrideWithValue(installer),
      vaultOpsProvider.overrideWithValue(AndroidVaultOps(errorLog)),
      vaultStoreProvider.overrideWithValue(HiveVaultStore(vaultBox)),
      vaultCredentialStoreProvider.overrideWithValue(HiveVaultCredentialStore(vaultCredsBox)),
      biometricAuthProvider.overrideWithValue(LocalAuthBiometric()),
    ],
    child: const KivoApp(),
  ));
}
