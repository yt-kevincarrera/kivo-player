import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/player/end_actions/end_actions.dart';
import 'package:kivo_player/ui/settings/sections/advanced_playback_section.dart';
import 'package:kivo_player/ui/settings/widgets/setting_choice.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<ProviderContainer> _pump(WidgetTester t, {String? subLang}) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  if (subLang != null) await s.update(s.current.copyWith(preferredSubtitleLanguage: subLang));
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()..movesToTrash = true),
  ]);
  addTearDown(c.dispose);
  await pumpLocalized(t, const AdvancedPlaybackSection(), container: c, theme: KivoTheme.dark());
  await t.pump();
  return c;
}

void main() {
  testWidgets('global end actions can be enabled, configured and disabled from settings', (t) async {
    final c = await _pump(t);
    await c.read(endActionsProvider.notifier).setSavedTrash(true);
    await t.pump();
    await t.ensureVisible(find.text(_l10n.endActionsGlobal));
    final row = find.ancestor(of: find.text(_l10n.endActionsGlobal),
        matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await t.pump();
    expect(c.read(endActionsProvider).trash, isTrue);
    await t.ensureVisible(find.text(_l10n.endActionsTitle));
    await t.tap(find.text(_l10n.endActionsTitle));
    await t.pumpAndSettle();
    final restart = find.byKey(const Key('end-after-restart'));
    await t.ensureVisible(restart);
    await t.tap(restart);
    await t.pump();
    expect(c.read(settingsProvider).endActionsAfter, 'restart');
    expect(c.read(endActionsProvider).after, AfterEnd.restart);
    final global = find.byKey(const Key('end-global-switch'));
    await t.ensureVisible(global);
    await t.tap(global);
    await t.pump();
    expect(c.read(settingsProvider).endActionsGlobal, isFalse);
    expect(c.read(endActionsProvider).isActive, isFalse);
    expect(c.read(settingsProvider).endActionsAfter, 'restart');
  });

  testWidgets('resume behavior choice persists', (t) async {
    final c = await _pump(t);
    await t.tap(find.text(_l10n.settingsAdvancedResumeOff));
    await t.pump();
    expect(c.read(settingsProvider).resumeBehavior, 'off');
  });

  testWidgets('toggling PiP-auto persists pipAutoOnHome', (t) async {
    final c = await _pump(t);
    final before = c.read(settingsProvider).pipAutoOnHome;
    // Scrolled into view: rows above it move it down as groups grow.
    await t.scrollUntilVisible(
        find.text(_l10n.settingsAdvancedPipAutoOnHome), 200,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    final pipRow = find.ancestor(
        of: find.text(_l10n.settingsAdvancedPipAutoOnHome),
        matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: pipRow, matching: find.byType(Switch)));
    await t.pump();
    expect(c.read(settingsProvider).pipAutoOnHome, !before);
  });

  testWidgets('resetting subtitle language to Automático clears it', (t) async {
    final c = await _pump(t, subLang: 'en');
    expect(c.read(settingsProvider).preferredSubtitleLanguage, 'en');
    // Scrolled into view rather than by a fixed offset: rows above it (the
    // Decodificación group) move it down whenever a group is added.
    await t.scrollUntilVisible(
        find.text(_l10n.settingsAdvancedPreferredSubtitleLang), 200,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    final subtitleRow = find.ancestor(
        of: find.text(_l10n.settingsAdvancedPreferredSubtitleLang),
        matching: find.byType(SettingChoice<String?>));
    await t.tap(find.descendant(
        of: subtitleRow, matching: find.text(_l10n.settingsAdvancedAutomaticOption)));
    await t.pump();
    expect(c.read(settingsProvider).preferredSubtitleLanguage, isNull);
  });
}
