enum ResumePromptKind { none, undo, ask }

class ResumePlan {
  final Duration startAt;
  final ResumePromptKind prompt;
  final Duration savedPosition;
  const ResumePlan(this.startAt, this.prompt, this.savedPosition);
}

/// Decides where to start playback and whether to surface a resume prompt.
/// [behavior] is `settings.resumeBehavior`: 'auto' | 'ask' | 'off'.
ResumePlan planResume(Duration? saved, String behavior) {
  final s = saved ?? Duration.zero;
  if (s <= Duration.zero || behavior == 'off') {
    return const ResumePlan(Duration.zero, ResumePromptKind.none, Duration.zero);
  }
  if (behavior == 'ask') {
    return ResumePlan(Duration.zero, ResumePromptKind.ask, s); // start at 0, offer to jump
  }
  return ResumePlan(s, ResumePromptKind.undo, s); // 'auto' (default): resume + undo toast
}
