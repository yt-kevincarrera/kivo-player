import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/resume/resume_plan.dart';

class ResumePromptState {
  final ResumePromptKind kind;
  final Duration savedPosition;
  const ResumePromptState(this.kind, this.savedPosition);
}

final resumePromptProvider = StateProvider<ResumePromptState?>((ref) => null);

/// Bottom-centered, auto-dismissing resume toast/prompt. `undo` = "Reanudado
/// desde M:SS · Reiniciar"; `ask` = "¿Reanudar desde M:SS?" with two choices.
class ResumePrompt extends ConsumerStatefulWidget {
  const ResumePrompt({super.key});
  @override
  ConsumerState<ResumePrompt> createState() => _ResumePromptState();
}

class _ResumePromptState extends ConsumerState<ResumePrompt> {
  Timer? _timer;
  void _clear() {
    _timer?.cancel();
    ref.read(resumePromptProvider.notifier).state = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(resumePromptProvider, (_, next) {
      _timer?.cancel();
      if (next != null) {
        _timer = Timer(
          Duration(seconds: next.kind == ResumePromptKind.ask ? 8 : 5),
          () => ref.read(resumePromptProvider.notifier).state = null,
        );
      }
    });

    final s = ref.watch(resumePromptProvider);
    if (s == null) return const SizedBox.shrink();
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final ctrl = ref.read(playerControllerProvider);
    final pos = fmtDuration(s.savedPosition);

    Widget action(String label, VoidCallback onTap) => TextButton(
          style: TextButton.styleFrom(foregroundColor: accent),
          onPressed: onTap,
          child: Text(label),
        );

    final children = <Widget>[];
    if (s.kind == ResumePromptKind.undo) {
      children.add(Flexible(child: Text('Reanudado desde $pos',
          style: const TextStyle(color: Colors.white))));
      children.add(action('Reiniciar', () { ref.read(restartRequestProvider.notifier).state++; _clear(); }));
    } else {
      children.add(Flexible(child: Text('¿Reanudar desde $pos?',
          style: const TextStyle(color: Colors.white))));
      children.add(action('Desde el inicio', () { ref.read(restartRequestProvider.notifier).state++; _clear(); }));
      children.add(action('Reanudar', () { ctrl.seekTo(s.savedPosition); _clear(); }));
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 96),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}
