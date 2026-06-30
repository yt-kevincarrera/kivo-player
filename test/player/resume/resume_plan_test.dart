import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/resume/resume_plan.dart';

void main() {
  test('off or no-saved → start at zero, no prompt', () {
    expect(planResume(const Duration(seconds: 90), 'off').prompt, ResumePromptKind.none);
    expect(planResume(null, 'auto').prompt, ResumePromptKind.none);
    expect(planResume(Duration.zero, 'auto').prompt, ResumePromptKind.none);
  });
  test('auto → resume at saved + undo toast', () {
    final p = planResume(const Duration(seconds: 90), 'auto');
    expect(p.startAt, const Duration(seconds: 90));
    expect(p.prompt, ResumePromptKind.undo);
    expect(p.savedPosition, const Duration(seconds: 90));
  });
  test('ask → start at zero, ask prompt carries saved position', () {
    final p = planResume(const Duration(seconds: 90), 'ask');
    expect(p.startAt, Duration.zero);
    expect(p.prompt, ResumePromptKind.ask);
    expect(p.savedPosition, const Duration(seconds: 90));
  });
}
