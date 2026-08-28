import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';

/// Long-press on a folder card. Hiding is a view filter, and the copy has to
/// say so — someone who knows the vault will otherwise assume this moves files.
Future<void> showFolderOptionsSheet(
    BuildContext context, WidgetRef ref, String folder) {
  final messenger = ScaffoldMessenger.of(context);
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
              title: Text('Ocultar de la biblioteca',
                  style: TextStyle(color: cs.onSurface)),
              subtitle: Text(
                  'No se borra ni se mueve nada: solo deja de aparecer en Kivo.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final s = ref.read(settingsProvider);
                if (s.excludedFolders.contains(folder)) return;
                await ref.read(settingsProvider.notifier).set(s.copyWith(
                    excludedFolders: [...s.excludedFolders, folder]));
                messenger.showSnackBar(SnackBar(
                  content: Text('$folder oculta'),
                  action: SnackBarAction(
                    label: 'Deshacer',
                    // Read the settings state fresh at tap time — closing over
                    // the snapshot from when the sheet was open would restore
                    // the wrong set if another folder got hidden in between.
                    onPressed: () {
                      final now = ref.read(settingsProvider);
                      ref.read(settingsProvider.notifier).set(now.copyWith(
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
