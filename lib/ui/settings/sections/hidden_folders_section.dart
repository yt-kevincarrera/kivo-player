import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';

/// Lists the folders hidden via [showFolderOptionsSheet] and lets you bring
/// each one back. Reads the stored names off [KivoSettings.excludedFolders]
/// directly (not the filtered library index), which is what keeps a folder
/// recoverable even after the index has filtered it out entirely.
class HiddenFoldersSection extends ConsumerWidget {
  const HiddenFoldersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final hidden =
        ref.watch(settingsProvider.select((s) => s.excludedFolders));

    return Scaffold(
      appBar: AppBar(title: const Text('Carpetas ocultas')),
      body: hidden.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No has ocultado ninguna carpeta.\n'
                  'Mantén pulsada una carpeta en Videos para ocultarla.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                for (final folder in hidden)
                  ListTile(
                    leading: Icon(Icons.folder_off_outlined,
                        color: cs.onSurfaceVariant),
                    title: Text(folder,
                        style: TextStyle(color: cs.onSurface)),
                    trailing: TextButton(
                      key: ValueKey('restore-$folder'),
                      onPressed: () {
                        final s = ref.read(settingsProvider);
                        ref.read(settingsProvider.notifier).set(s.copyWith(
                            excludedFolders: s.excludedFolders
                                .where((f) => f != folder)
                                .toList()));
                      },
                      child: Text('Mostrar',
                          style: TextStyle(color: cs.secondary)),
                    ),
                  ),
              ],
            ),
    );
  }
}
