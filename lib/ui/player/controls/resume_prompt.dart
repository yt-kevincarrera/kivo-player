import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/resume/resume_plan.dart';
import '../../widgets/swipe_dismiss_toast.dart';

class ResumePromptState {
  final ResumePromptKind kind;
  final Duration savedPosition;
  const ResumePromptState(this.kind, this.savedPosition);
}

final resumePromptProvider = StateProvider<ResumePromptState?>((ref) => null);

/// Bottom-centered, auto-dismissing resume toast/prompt. `undo` = "Reanudado
/// desde M:SS · Reiniciar" (4 s); `ask` = "¿Reanudar desde M:SS?" with two
/// choices (8 s — a real decision gets longer). Swipe it away in any
/// direction (see [SwipeDismissToast]).
class ResumePrompt extends ConsumerWidget {
  const ResumePrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(resumePromptProvider);
    if (s == null) return const SizedBox.shrink();
    void clear() {
      // Only if this prompt is still the one showing — a newer one (next
      // video) must not be cleared by the old one's exit animation.
      if (identical(ref.read(resumePromptProvider), s)) {
        ref.read(resumePromptProvider.notifier).state = null;
      }
    }

    final accent = Color(ref.watch(settingsProvider).accentColor);
    final pos = fmtDuration(s.savedPosition);
    final l10n = context.l10n;

    Widget action(String label, VoidCallback onTap) => TextButton(
          style: TextButton.styleFrom(foregroundColor: accent),
          onPressed: onTap,
          child: Text(label),
        );

    final children = <Widget>[];
    if (s.kind == ResumePromptKind.undo) {
      children.add(Flexible(child: Text(l10n.playerResumeUndoneMessage(pos),
          style: const TextStyle(color: Colors.white))));
      children.add(action(l10n.playerResumeRestartAction,
          () { ref.read(restartRequestProvider.notifier).state++; clear(); }));
    } else {
      children.add(Flexible(child: Text(l10n.playerResumeAskMessage(pos),
          style: const TextStyle(color: Colors.white))));
      children.add(action(l10n.playerResumeFromStartAction,
          () { ref.read(restartRequestProvider.notifier).state++; clear(); }));
      children.add(action(l10n.playerResumeAction, () {
        ref.read(playerControllerProvider).seekTo(s.savedPosition);
        clear();
      }));
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 96),
        child: SwipeDismissToast(
          key: ObjectKey(s),
          autoHide: Duration(seconds: s.kind == ResumePromptKind.ask ? 8 : 4),
          onDismissed: clear,
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}
