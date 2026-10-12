import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/media_file_ops_provider.dart';
import '../../../player/end_actions/end_actions.dart';
import '../state/zoom_state.dart';
import 'end_actions_panel.dart';

/// «🗑 Papelera ✕» floating over the bottom-left of the controls while
/// «Al terminar» is armed, so a mode that deletes files never runs unseen.
/// Lives with the controls (shown and hidden with them): it must not sit on
/// the video while watching. The ✕ turns everything off at once; the body
/// opens the panel.
class EndActionsChip extends ConsumerWidget {
  const EndActionsChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(endActionsProvider);
    // Mounted only while armed: a faded-out chip would still eat taps.
    if (!actions.isActive) return const SizedBox.shrink();
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final l10n = context.l10n;
    final toTrash = ref.watch(mediaFileOpsProvider).movesToTrash;
    // The zoom chip owns this corner while zoomed; sit just above it.
    final zoomed = ref.watch(zoomProvider.select((z) => z.active));
    final icon = actions.trash
        ? Icons.delete_outline_rounded
        : afterEndIcon(actions.after);
    final haptics = ref.watch(settingsProvider).hapticsOnGestures;

    return Padding(
      padding: EdgeInsets.only(bottom: zoomed ? 40 : 0),
      child: Container(
        key: const Key('end-actions-chip'),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: '${l10n.endActionsTitle}: '
                  '${endActionsSummary(l10n, actions, toTrash: toTrash)}',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(100)),
                onTap: () => showEndActionsPanel(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        endActionsSummary(l10n, actions, toTrash: toTrash),
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Tooltip(
              message: l10n.endActionsChipOffTooltip,
              child: InkWell(
                key: const Key('end-actions-chip-off'),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(100)),
                onTap: () {
                  ref.read(endActionsProvider.notifier).clear();
                  if (haptics) HapticFeedback.lightImpact();
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 7, 10, 7),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
