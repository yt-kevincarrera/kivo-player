import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../player/end_actions/trash_queue.dart';
import '../../widgets/swipe_dismiss_toast.dart';
import '../controls/resume_prompt.dart';

/// «Movido a la papelera · Deshacer» after a finished video is sent to the
/// trash. Its life is the trash queue's undo window: when that closes the
/// queue clears [trashUndoProvider] and this goes with it.
class TrashUndoToast extends ConsumerWidget {
  const TrashUndoToast({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final undo = ref.watch(trashUndoProvider);
    if (undo == null) return const SizedBox.shrink();
    final resumeUp = ref.watch(resumePromptProvider) != null;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final l10n = context.l10n;
    final message = undo.silent
        ? l10n.trashUndoMoved
        : undo.toTrash
            ? l10n.trashUndoOnExit
            : l10n.trashUndoDeleteOnExit;
    void clear() {
      if (identical(ref.read(trashUndoProvider), undo)) {
        ref.read(trashUndoProvider.notifier).state = null;
      }
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: resumeUp ? 152 : 96),
        child: SwipeDismissToast(
          key: ObjectKey(undo),
          // The queue's window decides; this only has to outlast it.
          autoHide: ref.watch(trashUndoWindowProvider) +
              const Duration(seconds: 1),
          onDismissed: clear,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(message, style: const TextStyle(color: Colors.white)),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: accent),
                onPressed: () => ref
                    .read(trashQueueProvider.notifier)
                    .undo(undo.entry.uri),
                child: Text(l10n.commonUndo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
