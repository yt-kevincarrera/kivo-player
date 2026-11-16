import 'dart:ui' show SemanticsFlag;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/player/audio/equalizer_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/platform/television_provider.dart';
import 'package:kivo_player/ui/settings/sections/end_actions_settings_screen.dart';
import 'package:kivo_player/ui/settings/sections/equalizer_section.dart';
import 'package:kivo_player/ui/settings/sections/advanced_playback_section.dart';
import 'package:kivo_player/ui/tv/tv_input_mode.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  final l = l10nFor(const Locale('es'));
  Future<ProviderContainer> pump(WidgetTester t, Widget screen) async {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final settings = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(settings),
        isTelevisionProvider.overrideWithValue(true),
        playbackEngineProvider.overrideWithValue(engine),
        mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()),
      ],
    );
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      c.dispose();
    });
    await pumpLocalized(
      t,
      TvInputMode(enabled: true, child: screen),
      container: c,
      theme: KivoTheme.television(),
    );
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('advanced TV choices can clear a nullable language preference', (
    t,
  ) async {
    final c = await pump(t, const AdvancedPlaybackSection());
    await c
        .read(settingsProvider.notifier)
        .set(c.read(settingsProvider).copyWith(preferredAudioLanguage: 'es'));
    await t.pumpAndSettle();
    final row = find.text(l.settingsAdvancedPreferredAudioLang);
    await t.ensureVisible(row);
    await t.pumpAndSettle();
    await t.tap(row);
    await t.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    final auto = find.text(l.settingsAdvancedAutomaticOption).last;
    await t.ensureVisible(auto);
    await t.tap(auto);
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).preferredAudioLanguage, isNull);
    expect(c.read(settingsProvider).preferredSubtitleLanguage, isNull);
  });

  testWidgets(
    'TV equalizer adjusts a band with arrows and preserves the other bands',
    (t) async {
      final c = await pump(t, const EqualizerSection());
      final first = find.text('31 Hz');
      await t.ensureVisible(first);
      await t.pumpAndSettle();
      await t.tap(first);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(c.read(equalizerProvider).gainsDb, [
        .5,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(
        t
            .getSemantics(find.bySemanticsLabel('31 Hz'))
            .hasFlag(SemanticsFlag.isFocused),
        isTrue,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, '62 Hz');
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(AppBar), findsNothing);
    },
  );

  testWidgets('TV end defaults preserve restart and its trash exclusion', (
    t,
  ) async {
    final c = await pump(t, const EndActionsSettingsScreen());
    final restart = find.byKey(const Key('end-default-after-restart'));
    await t.ensureVisible(restart);
    await t.pumpAndSettle();
    await t.tap(restart);
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).endActionsAfter, 'restart');
    final trash = find.byKey(const Key('end-default-trash'));
    expect(t.getSemantics(trash).hasFlag(SemanticsFlag.isEnabled), isFalse);
    expect(find.byType(RadioListTile), findsNothing);
    expect(find.byType(AppBar), findsNothing);
  });
}
