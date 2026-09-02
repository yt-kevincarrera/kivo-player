import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/player/audio/equalizer_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/settings/sections/equalizer_section.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
  ]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const EqualizerSection()),
  ));
  await t.pump();
  return c;
}

/// [EqualizerSection] flushes any pending debounced change from
/// `deactivate()` when it leaves the tree — see the comment on that override
/// for why `deactivate()` and not `dispose()`. That flush schedules real
/// async work (an engine call, a settings write), which the test framework's
/// own automatic end-of-test teardown has no chance to let settle before it
/// asserts no timers are left pending. Unmounting the screen ourselves and
/// then pumping past the 120ms debounce keeps that settling inside the test
/// body, where it belongs, instead of racing the framework's teardown.
Future<void> _settle(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('renders without overflowing at 360x640', (t) async {
    final view = t.view;
    view.physicalSize = const Size(360, 640);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    await _pump(t);

    expect(t.takeException(), isNull);
    expect(find.text('Ecualizador'), findsWidgets);
    expect(find.text('Plano'), findsOneWidget);
    expect(find.text('Graves'), findsOneWidget);
    expect(find.text('Voz'), findsOneWidget);
    expect(find.text('Agudos'), findsOneWidget);
    // Ten band frequency labels.
    for (final label in ['31', '62', '125', '250', '500', '1K', '2K', '4K', '8K', '16K']) {
      expect(find.text(label), findsOneWidget);
    }

    // The screen is tall enough at 360x640 to need scrolling to reach the
    // last card — that's the point of the test, not a bug: verify the rest
    // scrolls into view without ever overflowing.
    await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Restablecer'), findsOneWidget);

    await _settle(t);
  });

  testWidgets('toggling the switch persists enabled', (t) async {
    final c = await _pump(t);
    expect(c.read(equalizerProvider).enabled, false);

    await t.tap(find.byType(Switch));
    await t.pump();

    expect(c.read(equalizerProvider).enabled, true);
    await _settle(t);
  });

  testWidgets('tapping a preset chip applies its curve', (t) async {
    final c = await _pump(t);
    await t.tap(find.text('Graves'));
    await t.pump();
    expect(c.read(equalizerProvider).gainsDb[0], 6.0);
    await _settle(t);
  });

  testWidgets('Restablecer returns the curve to flat', (t) async {
    final c = await _pump(t);
    await t.tap(find.text('Graves'));
    await t.pump();
    expect(c.read(equalizerProvider).gainsDb[0], 6.0);

    await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await t.pump();
    await t.tap(find.text('Restablecer'));
    await t.pump();
    expect(c.read(equalizerProvider).gainsDb, List.filled(10, 0.0));
    await _settle(t);
  });
}
