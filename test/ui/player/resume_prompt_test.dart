import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/player/resume/resume_plan.dart';
import 'package:kivo_player/ui/player/controls/resume_prompt.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

void main() {
  Future<ProviderContainer> pump(WidgetTester tester, ResumePromptKind kind) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    await pumpLocalized(tester, const Scaffold(body: Stack(children: [Positioned.fill(child: ResumePrompt())])),
        container: c);
    c.read(resumePromptProvider.notifier).state =
        ResumePromptState(kind, const Duration(minutes: 1, seconds: 5));
    await tester.pump();
    return c;
  }

  testWidgets('"Reanudado · Reiniciar" stays 4 s, then animates out', (tester) async {
    final c = await pump(tester, ResumePromptKind.undo);
    expect(find.text(_l10n.playerResumeRestartAction), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 3800));
    expect(c.read(resumePromptProvider), isNotNull);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.read(resumePromptProvider), isNull);
    expect(find.text(_l10n.playerResumeRestartAction), findsNothing);
  });

  testWidgets('the "¿Reanudar?" choice keeps its 8 s', (tester) async {
    final c = await pump(tester, ResumePromptKind.ask);
    await tester.pump(const Duration(milliseconds: 7800));
    expect(c.read(resumePromptProvider), isNotNull);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.read(resumePromptProvider), isNull);
  });

  testWidgets('swiping it away clears it', (tester) async {
    final c = await pump(tester, ResumePromptKind.undo);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.timedDrag(find.textContaining('1:05'), const Offset(0, 120),
        const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.read(resumePromptProvider), isNull);
  });

  testWidgets('Reiniciar requests a restart and clears it', (tester) async {
    final c = await pump(tester, ResumePromptKind.undo);
    await tester.tap(find.text(_l10n.playerResumeRestartAction));
    await tester.pump();
    expect(c.read(restartRequestProvider), 1);
    expect(c.read(resumePromptProvider), isNull);
  });
}
