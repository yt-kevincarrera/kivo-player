import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/controls/top_bar.dart';
import 'package:kivo_player/ui/player/state/pip_state.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<ProviderContainer> _pumpTopBar(WidgetTester tester, {required bool supported}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final pip = FakePipController()..supported = supported;
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    pipControllerProvider.overrideWithValue(pip),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(
    const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
  );
  await pumpLocalized(tester, const Scaffold(body: TopBar()), container: c, theme: KivoTheme.dark());
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('PiP button hidden when unsupported', (tester) async {
    await _pumpTopBar(tester, supported: false);
    expect(find.byTooltip(_l10n.playerPipTooltip), findsNothing);
  });

  testWidgets('PiP button enters PiP when tapped', (tester) async {
    final c = await _pumpTopBar(tester, supported: true);
    expect(find.byTooltip(_l10n.playerPipTooltip), findsOneWidget);
    await tester.tap(find.byTooltip(_l10n.playerPipTooltip));
    await tester.pump();
    final pip = c.read(pipControllerProvider) as FakePipController;
    expect(pip.enterCount, 1);
  });

  test('pipModeProvider defaults to false and toggles', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(pipModeProvider), false);
    c.read(pipModeProvider.notifier).state = true;
    expect(c.read(pipModeProvider), true);
  });
}
