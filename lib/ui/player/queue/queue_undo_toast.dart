import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../player/open/video_source.dart';
import '../../../player/queue/queue_undo.dart';
import '../../widgets/swipe_dismiss_toast.dart';
import '../controls/resume_prompt.dart';

/// "Quitado de la cola · Deshacer" and friends, after each edit in the queue
/// strip. Same shell as the resume toast; sits just above it when both are up.
class QueueUndoToast extends ConsumerWidget {
  const QueueUndoToast({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final undo = ref.watch(queueUndoProvider);
    if (undo == null) return const SizedBox.shrink();
    final resumeUp = ref.watch(resumePromptProvider) != null;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final l10n = context.l10n;
    final message = switch (undo.kind) {
      QueueEditKind.moved => l10n.playerQueueMovedToast,
      QueueEditKind.playNext => l10n.playerQueuePlayNextToast,
      QueueEditKind.removed => l10n.playerQueueRemovedToast,
      QueueEditKind.shuffleReset => l10n.playerQueueShuffleResetToast,
    };
    void clear() {
      // A newer edit's toast must not be cleared by this one's exit.
      if (identical(ref.read(queueUndoProvider), undo)) {
        ref.read(queueUndoProvider.notifier).state = null;
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
          autoHide: const Duration(seconds: 4),
          onDismissed: clear,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(message, style: const TextStyle(color: Colors.white)),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: accent),
                onPressed: () =>
                    ref.read(currentVideoProvider.notifier).undoQueueEdit(),
                child: Text(l10n.commonUndo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
