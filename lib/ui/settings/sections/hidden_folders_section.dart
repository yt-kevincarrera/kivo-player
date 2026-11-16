import '../widgets/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../tv/tv_input_mode.dart';
import '../../tv/tv_panel.dart';

/// Lists the folders hidden via [showFolderOptionsSheet] and lets you bring
/// each one back. Reads the stored names off [KivoSettings.excludedFolders]
/// directly (not the filtered library index), which is what keeps a folder
/// recoverable even after the index has filtered it out entirely.
class HiddenFoldersSection extends ConsumerWidget {
  const HiddenFoldersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final hidden = ref.watch(settingsProvider.select((s) => s.excludedFolders));

    if (TvInputMode.of(context)) {
      return SettingsSectionPage(
        title: l10n.settingsHiddenFoldersTitle,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(120, 12, 120, 24),
          children: [
            if (hidden.isEmpty)
              Text(
                l10n.settingsHiddenFoldersEmpty,
                style: const TextStyle(fontSize: 22),
              ),
            for (final folder in hidden)
              TvOptionRow(
                key: ValueKey('restore-$folder'),
                label: folder,
                value: l10n.settingsHiddenFoldersShowAction,
                icon: Icons.folder_outlined,
                onPressed: () {
                  final s = ref.read(settingsProvider);
                  ref
                      .read(settingsProvider.notifier)
                      .set(
                        s.copyWith(
                          excludedFolders: s.excludedFolders
                              .where((f) => f != folder)
                              .toList(),
                        ),
                      );
                },
              ),
          ],
        ),
      );
    }
    return SettingsSectionPage(
      title: l10n.settingsHiddenFoldersTitle,
      body: hidden.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.settingsHiddenFoldersEmpty,
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
                    leading: Icon(
                      Icons.folder_off_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                    title: Text(folder, style: TextStyle(color: cs.onSurface)),
                    trailing: TextButton(
                      key: ValueKey('restore-$folder'),
                      onPressed: () {
                        final s = ref.read(settingsProvider);
                        ref
                            .read(settingsProvider.notifier)
                            .set(
                              s.copyWith(
                                excludedFolders: s.excludedFolders
                                    .where((f) => f != folder)
                                    .toList(),
                              ),
                            );
                      },
                      child: Text(
                        l10n.settingsHiddenFoldersShowAction,
                        style: TextStyle(color: cs.secondary),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
