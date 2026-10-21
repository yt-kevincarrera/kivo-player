import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/media_file_ops_provider.dart';
import '../../../player/end_actions/end_flow.dart';
import 'end_actions_panel.dart';

/// «🗑 Papelera ✕» in the bottom controls above the seek bar while
/// «Al terminar» is armed, so a mode that deletes files never runs unseen.
/// Lives with the controls (shown and hidden with them): it must not sit on
/// the video while watching. The body opens the panel, ⏭ is «Terminar ya»
/// and ✕ turns everything off at once.
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
    final icon = actions.trash && actions.after != AfterEnd.restart
        ? Icons.delete_outline_rounded
        : afterEndIcon(actions.after);
    final haptics = ref.watch(settingsProvider).hapticsOnGestures;

    return Container(
      key: const Key('end-actions-chip'),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Semantics(
              button: true,
              label: l10n.endActionsChipSemantics(
                endActionsSummary(l10n, actions, toTrash: toTrash),
              ),
              excludeSemantics: true,
              onTap: () => showEndActionsPanel(context),
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(100),
                ),
                onTap: () => showEndActionsPanel(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 6, 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: accent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          endActionsSummary(l10n, actions, toTrash: toTrash),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // «Terminar ya» right here, for the credits: no menu to dig in.
          IconButton(
            key: const Key('end-actions-chip-finish'),
            tooltip: l10n.endActionsFinishNow,
            onPressed: () => ref.read(finishNowProvider.notifier).state++,
            icon: Icon(Icons.skip_next_rounded, size: 20, color: accent),
          ),
          IconButton(
            key: const Key('end-actions-chip-off'),
            tooltip: l10n.endActionsChipOffTooltip,
            onPressed: () {
              ref.read(endActionsProvider.notifier).clear();
              if (haptics) HapticFeedback.lightImpact();
            },
            icon: const Icon(
              Icons.close_rounded,
              size: 20,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
