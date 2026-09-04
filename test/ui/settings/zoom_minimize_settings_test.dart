import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/sections/advanced_playback_section.dart';
import 'package:kivo_player/ui/settings/sections/playback_gestures_section.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<ProviderContainer> _pump(WidgetTester t, Widget section) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await pumpLocalized(t, section, container: c, theme: KivoTheme.dark());
  await t.pump();
  return c;
}

Future<void> _scrollTo(WidgetTester t, Finder target) async {
  await t.scrollUntilVisible(target, 300, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the Zoom switch toggles pinchZoom', (t) async {
    final c = await _pump(t, const PlaybackGesturesSection());
    await _scrollTo(t, find.text(_l10n.settingsGesturesPinchZoom));

    expect(c.read(settingsProvider).pinchZoom, true);
    // The switch sits in the same row as its title.
    await t.tap(find.descendant(
        of: find.ancestor(of: find.text(_l10n.settingsGesturesPinchZoom), matching: find.byType(Row)).first,
        matching: find.byType(Switch)));
    await t.pump();

    expect(c.read(settingsProvider).pinchZoom, false);
  });

  testWidgets('the zoom max segmented persists zoomMax', (t) async {
    final c = await _pump(t, const PlaybackGesturesSection());
    await _scrollTo(t, find.text('6×'));

    expect(c.read(settingsProvider).zoomMax, 4.0);
    await t.tap(find.text('6×'));
    await t.pump();

    expect(c.read(settingsProvider).zoomMax, 6.0);
  });

  testWidgets('the reset-mode segmented persists zoomResetMode', (t) async {
    final c = await _pump(t, const PlaybackGesturesSection());
    await _scrollTo(t, find.text(_l10n.settingsGesturesZoomResetVideo));

    expect(c.read(settingsProvider).zoomResetMode, 'exit');
    await t.tap(find.text(_l10n.settingsGesturesZoomResetVideo));
    await t.pump();
    expect(c.read(settingsProvider).zoomResetMode, 'video');

    await t.tap(find.text(_l10n.settingsGesturesZoomResetNever));
    await t.pump();
    expect(c.read(settingsProvider).zoomResetMode, 'never');
  });

  testWidgets('the advanced section toggles minimizeKeepsPlaying', (t) async {
    final c = await _pump(t, const AdvancedPlaybackSection());
    await _scrollTo(t, find.text(_l10n.settingsAdvancedMinimizeKeepsPlaying));

    expect(c.read(settingsProvider).minimizeKeepsPlaying, false);
    await t.tap(find.descendant(
        of: find
            .ancestor(
                of: find.text(_l10n.settingsAdvancedMinimizeKeepsPlaying),
                matching: find.byType(Row))
            .first,
        matching: find.byType(Switch)));
    await t.pump();

    expect(c.read(settingsProvider).minimizeKeepsPlaying, true);
  });
}
