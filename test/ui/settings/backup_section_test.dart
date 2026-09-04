import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/backup/backup_file.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart'; // resumeServiceProvider
import 'package:kivo_player/player/playlists/playlist.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/ui/settings/sections/backup_section.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_store.dart';

import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

/// A fake FilePicker.platform: `extends FilePicker` (not `implements`) so
/// the base constructor supplies the private verification token the real
/// package checks in its `platform` setter.
class _FakeFilePicker extends FilePicker {
  /// What the next [pickFiles] call returns as the picked file's bytes, or
  /// null to simulate the user cancelling the dialog.
  String? nextPickedJson;
  final List<Uint8List?> savedBytes = [];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final json = nextPickedJson;
    if (json == null) return null;
    final bytes = Uint8List.fromList(utf8.encode(json));
    return FilePickerResult(
        [PlatformFile(name: 'backup.json', size: bytes.length, bytes: bytes)]);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    savedBytes.add(bytes);
    return '/downloads/${fileName ?? 'backup.json'}';
  }
}

class _Env {
  final ProviderContainer container;
  final InMemoryPlaylistStore playlists;
  const _Env(this.container, this.playlists);
}

Future<_Env> _pump(WidgetTester t, {required String backupJson}) async {
  FilePicker.platform = _FakeFilePicker()..nextPickedJson = backupJson;

  final settingsService = await SettingsService.load(InMemorySettingsStore());
  final playlists = InMemoryPlaylistStore();
  final container = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(settingsService),
    resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
    playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    playlistStoreProvider.overrideWithValue(playlists),
    bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
    trackPrefsStoreProvider.overrideWithValue(InMemoryTrackPrefsStore()),
    vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
    appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.14.2')),
  ]);
  addTearDown(container.dispose);
  await pumpLocalized(t, const BackupSection(), container: container, theme: KivoTheme.dark());
  await t.pump();
  return _Env(container, playlists);
}

String _twoNewPlaylistsBackup() => const BackupFile(
      app: '1.0.0',
      createdAtMs: 0,
      settings: {},
      resume: {},
      played: {},
      trackPrefs: {},
      playlists: [
        Playlist(id: 'p1', name: 'Serie 1', createdAtMs: 1, entries: []),
        Playlist(id: 'p2', name: 'Serie 2', createdAtMs: 2, entries: []),
      ],
      bookmarks: {},
      vault: [],
    ).toJson();

void main() {
  testWidgets('restore dialog shows the plan\'s counts', (t) async {
    await _pump(t, backupJson: _twoNewPlaylistsBackup());

    await t.tap(find.text(_l10n.settingsBackupRestoreTitle));
    await t.pumpAndSettle();

    expect(find.text(_l10n.settingsBackupRestoreTitle), findsWidgets); // dialog title + row
    expect(find.textContaining(_l10n.settingsBackupRestoreItemPlaylists(2)), findsOneWidget);
  });

  testWidgets('Cancelar in the confirm dialog applies nothing', (t) async {
    final env = await _pump(t, backupJson: _twoNewPlaylistsBackup());

    await t.tap(find.text(_l10n.settingsBackupRestoreTitle));
    await t.pumpAndSettle();
    expect(find.textContaining(_l10n.settingsBackupRestoreItemPlaylists(2)), findsOneWidget);

    await t.tap(find.text(_l10n.commonCancel));
    await t.pumpAndSettle();

    expect(env.container.read(playlistStoreProvider).all(), isEmpty);
    expect(env.playlists.all(), isEmpty);
  });

  testWidgets('Restaurar in the confirm dialog applies the plan', (t) async {
    final env = await _pump(t, backupJson: _twoNewPlaylistsBackup());

    await t.tap(find.text(_l10n.settingsBackupRestoreTitle));
    await t.pumpAndSettle();
    await t.tap(find.text(_l10n.settingsBackupRestoreConfirmAction));
    await t.pumpAndSettle();

    expect(env.container.read(playlistStoreProvider).all(), hasLength(2));
    expect(find.text(_l10n.settingsBackupRestoredSnackbar), findsOneWidget);
  });

  testWidgets('a newer-format backup shows a typed error dialog, not a raw exception',
      (t) async {
    final badJson = jsonEncode({'kivo': kBackupFormatVersion + 1});
    await _pump(t, backupJson: badJson);

    await t.tap(find.text(_l10n.settingsBackupRestoreTitle));
    await t.pumpAndSettle();

    expect(find.text(_l10n.settingsBackupReadFailedDialogTitle), findsOneWidget);
    // The dialog shows the localized message, not BackupTooNewException's
    // own hardcoded-Spanish toString() (that stays as the raw/log text —
    // see lib/ui/settings/sections/backup_section.dart's catch clause).
    expect(find.text(_l10n.settingsBackupTooNewMessage), findsOneWidget);
  });
}
