import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backup/backup_file.dart';
import '../../../core/backup/backup_merge.dart';
import '../../../core/backup/backup_service.dart';
import '../../../l10n/l10n.dart';
import '../../../core/errors/kivo_failure.dart';
import '../../../core/errors/error_log_provider.dart';
import '../../widgets/failure_l10n.dart';
import '../search/settings_search.dart';
import '../widgets/setting_anchor.dart';
import '../widgets/setting_tiles.dart';
import '../../widgets/readable_width.dart';

class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  bool _busy = false;
  bool _working = false;
  KivoOp _operation = KivoOp.backupRead;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsBackupTitle)),
      body: SettingsScrollBody(
        padding: readablePadding(
          context,
          const EdgeInsets.fromLTRB(14, 12, 14, 28),
        ),
        children: [
          if (_working) ...[
            LinearProgressIndicator(semanticsLabel: l10n.settingsBackupWorking),
            const SizedBox(height: 12),
          ],
          AbsorbPointer(
            absorbing: _busy,
            child: SettingsCard(
              children: [
                SettingAnchor(
                  id: SettingIds.backupExport,
                  child: SettingNavRow(
                    icon: Icons.upload_outlined,
                    title: l10n.settingsBackupExport,
                    subtitle: l10n.settingsBackupExportSubtitle,
                    onTap: () =>
                        _run(() => _export(context, ref), KivoOp.backupExport),
                  ),
                ),
                SettingAnchor(
                  id: SettingIds.backupRestore,
                  child: SettingNavRow(
                    icon: Icons.download_outlined,
                    title: l10n.settingsBackupRestoreTitle,
                    subtitle: l10n.settingsBackupRestoreSubtitle,
                    onTap: () =>
                        _run(() => _restore(context, ref), KivoOp.backupRead),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, KivoOp operation) async {
    if (!mounted || _busy) return;
    setState(() {
      _busy = true;
      _working = true;
    });
    _operation = operation;
    try {
      await action();
    } on BackupTooNewException {
      if (mounted) {
        await _showError(context, context.l10n.settingsBackupTooNewMessage);
      }
    } on BackupFormatException {
      if (mounted) {
        await _showError(
          context,
          context.l10n.settingsBackupInvalidFileMessage,
        );
      }
    } on FormatException {
      // Invalid UTF-8 is an invalid backup too. Never log its source bytes.
      if (mounted) {
        await _showError(
          context,
          context.l10n.settingsBackupInvalidFileMessage,
        );
      }
    } catch (error) {
      if (!mounted) return;
      final failure = KivoFailure(_operation, error);
      ref.read(errorLogProvider).record(failure);
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${failureMessage(l10n, _operation)} (${failure.code})',
          ),
          action: SnackBarAction(
            label: l10n.errorRetryAction,
            onPressed: () => _run(action, operation),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _working = false;
        });
      }
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final json = await ref.read(backupServiceProvider).exportJson();
    if (!context.mounted) return;
    final bytes = Uint8List.fromList(utf8.encode(json));
    final now = DateTime.now();
    final fileName = 'kivo-${_dateStamp(now)}.kivo.json';

    final path = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          path != null
              ? l10n.settingsBackupExportSavedSnackbar
              : l10n.settingsBackupExportCancelledSnackbar,
        ),
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (!context.mounted || result == null || result.files.isEmpty) {
      return; // cancelado
    }

    final picked = result.files.single;
    String jsonStr;
    final data = picked.bytes;
    if (data != null) {
      jsonStr = utf8.decode(data);
    } else if (picked.path != null) {
      jsonStr = await File(picked.path!).readAsString();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsBackupReadFileFailedSnackbar)),
      );
      return;
    }

    if (!context.mounted) return;
    final plan = await ref.read(backupServiceProvider).plan(jsonStr);
    if (!context.mounted) return;
    setState(() => _working = false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsBackupRestoreTitle),
        content: Text(
          _describeRestore(dialogContext, summarizeRestorePlan(plan)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsBackupRestoreConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    setState(() => _working = true);
    _operation = KivoOp.backupRestore;

    await ref.read(backupServiceProvider).apply(plan);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsBackupRestoredSnackbar)),
    );
  }

  Future<void> _showError(BuildContext context, String message) async {
    if (!context.mounted) return;
    setState(() => _working = false);
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsBackupReadFailedDialogTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  /// Phrases [summary] as one sentence, e.g. «Se añadirán 3 listas, 40
  /// marcadores y 12 posiciones. Los ajustes se reemplazarán.» — an ICU
  /// plural per changed section, joined in Dart with the locale's own join
  /// word so the clause list reads naturally in both languages regardless of
  /// how many sections actually changed.
  String _describeRestore(BuildContext context, RestoreSummary summary) {
    final l10n = context.l10n;
    final items = <String>[
      if (summary.playlistsAdded > 0)
        l10n.settingsBackupRestoreItemPlaylists(summary.playlistsAdded),
      if (summary.bookmarksAdded > 0)
        l10n.settingsBackupRestoreItemBookmarks(summary.bookmarksAdded),
      if (summary.positionsChanged > 0)
        l10n.settingsBackupRestoreItemPositions(summary.positionsChanged),
      if (summary.watchedVideosAdded > 0)
        l10n.settingsBackupRestoreItemWatchedVideos(summary.watchedVideosAdded),
      if (summary.completedVideosAdded > 0)
        l10n.settingsBackupRestoreItemCompletedVideos(
          summary.completedVideosAdded,
        ),
      if (summary.hiddenVideosAdded > 0)
        l10n.settingsBackupRestoreItemHiddenVideos(summary.hiddenVideosAdded),
      if (summary.trackSettingsChanged > 0)
        l10n.settingsBackupRestoreItemTrackSettings(
          summary.trackSettingsChanged,
        ),
    ];

    final sentence = StringBuffer();
    if (items.isEmpty) {
      sentence.write(l10n.settingsBackupRestoreNothingNew);
    } else {
      sentence.write(
        l10n.settingsBackupRestoreWillAdd(
          _joinItems(items, l10n.settingsBackupRestoreJoinWord),
        ),
      );
    }
    if (summary.settingsWillReplace) {
      if (items.isNotEmpty) sentence.write(' ');
      sentence.write(l10n.settingsBackupRestoreSettingsReplace);
    }
    return sentence.toString();
  }

  String _joinItems(List<String> items, String joinWord) {
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} $joinWord ${items.last}';
  }

  String _dateStamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
