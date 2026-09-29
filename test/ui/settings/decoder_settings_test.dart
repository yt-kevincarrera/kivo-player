import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/ui/settings/sections/advanced_playback_section.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<(ProviderContainer, InMemoryTrackPrefsStore)> _pump(WidgetTester t,
    {String mode = 'auto'}) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  await s.update(s.current.copyWith(decoderMode: mode));
  final prefs = InMemoryTrackPrefsStore();
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    trackPrefsStoreProvider.overrideWithValue(prefs),
  ]);
  addTearDown(c.dispose);
  await t.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await pumpLocalized(t, const AdvancedPlaybackSection(),
      container: c, theme: KivoTheme.dark());
  await t.pump();
  return (c, prefs);
}

void main() {
  testWidgets('the default decoder choice persists', (t) async {
    final (c, _) = await _pump(t);
    await t.tap(find.text(_l10n.settingsDecoderSoftware));
    await t.pump();
    expect(c.read(settingsProvider).decoderMode, 'sw');
  });

  testWidgets('automatic switching and its wait only show in Automático',
      (t) async {
    await _pump(t, mode: 'sw');
    expect(find.text(_l10n.settingsDecoderAutoFallback), findsNothing);
    expect(find.text(_l10n.settingsDecoderStallSeconds), findsNothing);
  });

  testWidgets('the wait steps within 1–10 s', (t) async {
    final (c, _) = await _pump(t);
    expect(find.text('3 s'), findsOneWidget);
    final row = find.ancestor(
        of: find.text(_l10n.settingsDecoderStallSeconds),
        matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: row, matching: find.text('+')).first);
    await t.pump();
    expect(c.read(settingsProvider).decoderStallSeconds, 4);
  });

  testWidgets('turning automatic switching off hides the wait', (t) async {
    final (c, _) = await _pump(t);
    final row = find.ancestor(
        of: find.text(_l10n.settingsDecoderAutoFallback),
        matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await t.pump();
    expect(c.read(settingsProvider).decoderAutoFallback, isFalse);
    expect(find.text(_l10n.settingsDecoderStallSeconds), findsNothing);
  });

  testWidgets('forgetting saved decoders clears them and says how many',
      (t) async {
    final (_, prefs) = await _pump(t);
    await prefs.put('a.mkv', const VideoTrackPrefs(decoder: 'sw'));
    await prefs.put('b.mkv', const VideoTrackPrefs(decoder: 'hw'));
    await t.tap(find.text(_l10n.settingsDecoderForget));
    await t.pump();
    await t.pump();
    expect(prefs.forKey('a.mkv'), isNull);
    expect(prefs.forKey('b.mkv'), isNull);
    expect(find.text(_l10n.settingsDecoderForgotSnackbar(2)), findsOneWidget);
  });
}
