import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';

/// Long-press on a folder card. Hiding is a view filter, and the copy has to
/// say so — someone who knows the vault will otherwise assume this moves files.
Future<void> showFolderOptionsSheet(
    BuildContext context, WidgetRef ref, String folder) {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  // Captured up front for the same reason as the messenger: `ref` belongs to
  // the FolderGrid, and the SnackBar below outlives a tab switch that unmounts
  // it, so reading through it when "Deshacer" is tapped can throw. The service
  // is the very object the notifier writes through, so `current` is still the
  // fresh state the undo needs — no stale snapshot.
  final settings = ref.read(settingsProvider.notifier);
  final settingsService = ref.read(settingsServiceProvider);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(folder,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            ListTile(
              leading: Icon(Icons.visibility_off_outlined,
                  color: cs.onSurfaceVariant),
              title: Text(l10n.folderHideTitle,
                  style: TextStyle(color: cs.onSurface)),
              subtitle: Text(
                  l10n.folderHideSubtitle,
                  style: TextStyle(color: cs.onSurfaceVariant)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final s = settingsService.current;
                if (s.excludedFolders.contains(folder)) return;
                await settings.set(s.copyWith(
                    excludedFolders: [...s.excludedFolders, folder]));
                messenger.showSnackBar(SnackBar(
                  content: Text(l10n.folderHiddenSnackbar(folder)),
                  action: SnackBarAction(
                    label: l10n.commonUndo,
                    // Read the settings state fresh at tap time — closing over
                    // the snapshot from when the sheet was open would restore
                    // the wrong set if another folder got hidden in between.
                    onPressed: () {
                      final now = settingsService.current;
                      settings.set(now.copyWith(
                          excludedFolders: now.excludedFolders
                              .where((f) => f != folder)
                              .toList()));
                    },
                  ),
                ));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
