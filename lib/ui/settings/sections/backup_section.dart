import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backup/backup_file.dart';
import '../../../core/backup/backup_merge.dart';
import '../../../core/backup/backup_service.dart';
import '../widgets/setting_tiles.dart';

class BackupSection extends ConsumerWidget {
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Copia de seguridad')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          SettingsCard(children: [
            SettingNavRow(
              icon: Icons.upload_outlined,
              title: 'Exportar copia',
              subtitle: 'Guarda tus listas, marcadores y ajustes en un archivo',
              onTap: () => _export(context, ref),
            ),
            SettingNavRow(
              icon: Icons.download_outlined,
              title: 'Restaurar copia',
              subtitle: 'Añade lo que haya en un archivo de copia guardado antes',
              onTap: () => _restore(context, ref),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final json = await ref.read(backupServiceProvider).exportJson();
    final bytes = Uint8List.fromList(utf8.encode(json));
    final now = DateTime.now();
    final fileName = 'kivo-${_dateStamp(now)}.kivo.json';

    final path = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    messenger.showSnackBar(SnackBar(
      content: Text(path != null ? 'Copia guardada' : 'Cancelado'),
    ));
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return; // cancelado

    final picked = result.files.single;
    String jsonStr;
    final data = picked.bytes;
    if (data != null) {
      jsonStr = utf8.decode(data);
    } else if (picked.path != null) {
      jsonStr = await File(picked.path!).readAsString();
    } else {
      messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo leer el archivo')));
      return;
    }

    RestorePlan plan;
    try {
      plan = await ref.read(backupServiceProvider).plan(jsonStr);
    } on BackupTooNewException catch (e) {
      if (!context.mounted) return;
      await _showError(context, e.toString());
      return;
    } on BackupFormatException catch (e) {
      if (!context.mounted) return;
      await _showError(context, e.toString());
      return;
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restaurar copia'),
        content: Text(describeRestorePlan(plan)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(backupServiceProvider).apply(plan);
    messenger.showSnackBar(const SnackBar(content: Text('Copia restaurada')));
  }

  Future<void> _showError(BuildContext context, String message) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No se pudo leer la copia'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  String _dateStamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
