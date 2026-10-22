import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/media_file_ops_provider.dart';
import '../../../player/end_actions/end_actions.dart';
import '../../player/end_actions/end_actions_panel.dart';
import '../../widgets/readable_width.dart';
import '../widgets/setting_tiles.dart';

/// Persistent defaults, separate from the player's queue-specific actions.
class EndActionsSettingsScreen extends ConsumerWidget {
  const EndActionsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final actions = EndActions.defaults(ref.watch(settingsProvider));
    final notifier = ref.read(endActionsProvider.notifier);
    final toTrash = ref.watch(mediaFileOpsProvider).movesToTrash;
    final restarting = actions.after == AfterEnd.restart;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.endActionsTitle)),
      body: SafeArea(
        child: SettingsScrollBody(
          padding: readablePadding(
            context,
            const EdgeInsets.fromLTRB(14, 12, 14, 28),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 16),
              child: Text(
                l10n.endActionsDefaultsHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            SettingsCard(
              children: [
                SwitchListTile(
                  key: const Key('end-default-trash'),
                  title: Text(
                    toTrash
                        ? l10n.endActionsTrashTitle
                        : l10n.endActionsDeleteTitle,
                  ),
                  subtitle: Text(
                    restarting
                        ? l10n.endActionsTrashRestart
                        : l10n.endActionsDefaultTrashHint,
                  ),
                  value: actions.trash,
                  onChanged: restarting
                      ? null
                      : (on) => notifier.setDefaults(trash: on),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
              child: Text(
                l10n.endActionsAfterTitle,
                style: theme.textTheme.titleSmall,
              ),
            ),
            RadioGroup<AfterEnd>(
              groupValue: actions.after,
              onChanged: (after) {
                if (after != null) notifier.setDefaults(after: after);
              },
              child: SettingsCard(
                children: [
                  for (final after in AfterEnd.values)
                    RadioListTile<AfterEnd>(
                      key: Key('end-default-after-${after.name}'),
                      value: after,
                      activeColor: theme.colorScheme.onSurface,
                      title: Text(afterEndLabel(l10n, after)),
                      subtitle: after == AfterEnd.restart
                          ? Text(l10n.endActionsDefaultRestartHint)
                          : after == AfterEnd.screenOff
                          ? Text(l10n.endActionsAfterScreenOffHint)
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
