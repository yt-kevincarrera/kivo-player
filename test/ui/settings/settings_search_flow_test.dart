import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/all_files_access_provider.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/player/decoder/decoder_mode.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/settings/search/settings_search.dart';
import 'package:kivo_player/ui/settings/search/settings_search_state.dart';
import 'package:kivo_player/ui/settings/sections/about_section.dart';
import 'package:kivo_player/ui/settings/sections/advanced_playback_section.dart';
import 'package:kivo_player/ui/settings/sections/backup_section.dart';
import 'package:kivo_player/ui/settings/sections/equalizer_section.dart';
import 'package:kivo_player/ui/settings/sections/general_section.dart';
import 'package:kivo_player/ui/settings/sections/interface_section.dart';
import 'package:kivo_player/ui/settings/sections/playback_gestures_section.dart';
import 'package:kivo_player/ui/settings/settings_screen.dart';
import 'package:kivo_player/ui/settings/widgets/setting_anchor.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<ProviderContainer> _container(KivoSettings Function(KivoSettings) tweak) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  await svc.update(tweak(svc.current));
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.0.0')),
    updateCheckerProvider.overrideWithValue(FakeUpdateChecker()),
    playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
    allFilesAccessProvider.overrideWithValue(FakeAllFilesAccess(granted: false)),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// Every conditional control on screen, so each section mounts all its anchors.
KivoSettings _everythingShown(KivoSettings s) => s.copyWith(
      showInfoOverlay: true,
      decoderMode: DecoderMode.auto.id,
      decoderAutoFallback: true,
      nightMode: true,
      voiceBoost: true,
    );

Widget? _section(SettingsPage page) => switch (page) {
      SettingsPage.general => const GeneralSettingsSection(),
      SettingsPage.gestures => const PlaybackGesturesSection(),
      SettingsPage.interface => const InterfaceSettingsSection(),
      SettingsPage.advanced => const AdvancedPlaybackSection(),
      SettingsPage.equalizer => const EqualizerSection(),
      SettingsPage.backup => const BackupSection(),
      SettingsPage.about => const AboutSection(),
      SettingsPage.vault => null,
    };

/// Unmounts first so EqualizerSection's deactivate() flush settles inside the
/// test (see equalizer_section_test).
Future<void> _settle(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(milliseconds: 200));
}

/// The flash strength on [anchorId]'s overlay right now, 0 at rest.
double _flashAlpha(WidgetTester t, String anchorId) {
  final anchor = find.byWidgetPredicate((w) => w is SettingAnchor && w.id == anchorId);
  final box = t.widget<DecoratedBox>(find
      .descendant(of: anchor, matching: find.byType(DecoratedBox))
      .first);
  return ((box.decoration as BoxDecoration).color ?? Colors.transparent).a;
}

/// Pumps [total] in small steps and returns the brightest flash seen.
Future<double> _peakFlash(WidgetTester t, String anchorId,
    {Duration total = const Duration(seconds: 3)}) async {
  var peak = 0.0;
  for (var e = Duration.zero; e < total; e += const Duration(milliseconds: 50)) {
    await t.pump(const Duration(milliseconds: 50));
    if (find.byWidgetPredicate((w) => w is SettingAnchor && w.id == anchorId).evaluate().isNotEmpty) {
      final a = _flashAlpha(t, anchorId);
      if (a > peak) peak = a;
    }
  }
  return peak;
}

Future<void> _search(WidgetTester t, String query) async {
  await t.tap(find.byTooltip(_l10n.settingsSearchTooltip));
  await t.pumpAndSettle();
  await t.enterText(find.byKey(const ValueKey('settings-search-field')), query);
  await t.pump();
}

void main() {
  // The contract between the index and the screens: a result whose anchor
  // isn't mounted would open the section and highlight nothing.
  for (final page in SettingsPage.values.where((p) => p != SettingsPage.vault)) {
    testWidgets('every indexed ${page.name} setting has a mounted anchor, and nothing more', (t) async {
      final c = await _container(_everythingShown);
      await pumpLocalized(t, _section(page)!, container: c, theme: KivoTheme.dark());
      await t.pumpAndSettle();

      final mounted = {for (final a in t.widgetList<SettingAnchor>(find.byType(SettingAnchor))) a.id};
      final indexed = {
        for (final e in settingsSearchEntries)
          if (e.page == page && e.id != null) e.id!
      };
      expect(mounted, indexed);
      await _settle(t);
    });
  }

  testWidgets('a result opens its section, scrolls to the setting and flashes it in the accent colour',
      (t) async {
    const accent = 0xFF5B9BE8;
    final c = await _container((s) => s.copyWith(accentColor: accent));
    await pumpLocalized(t, const SettingsScreen(), container: c, theme: KivoTheme.dark());
    await t.pumpAndSettle();

    // The last row of the longest section: far below the fold.
    await _search(t, 'escalones');
    final hit = find.byKey(const ValueKey('settings-hit-${SettingIds.holdRightDetents}'));
    expect(hit, findsOneWidget);
    await t.tap(hit);

    final peak = await _peakFlash(t, SettingIds.holdRightDetents);
    expect(peak, greaterThan(0.1), reason: 'the setting must visibly flash');
    await t.pumpAndSettle();

    expect(find.byType(PlaybackGesturesSection), findsOneWidget);
    final anchor = find.byWidgetPredicate((w) => w is SettingAnchor && w.id == SettingIds.holdRightDetents);
    final viewport = t.getRect(find.byType(Scrollable).last);
    final row = t.getRect(anchor);
    expect(viewport.overlaps(row), isTrue, reason: 'scrolled into view');

    // The flash is the accent, and it fades out completely.
    final box = t.widget<DecoratedBox>(find.descendant(of: anchor, matching: find.byType(DecoratedBox)).first);
    final color = (box.decoration as BoxDecoration).color!;
    expect(color.withValues(alpha: 1).toARGB32(), accent);
    expect(color.a, 0);
    expect(c.read(settingsHighlightProvider), isNull, reason: 'consumed, so it never flashes again');
  });

  testWidgets('a setting hidden behind a switch highlights that switch instead', (t) async {
    final c = await _container((s) => s.copyWith(showInfoOverlay: false));
    await pumpLocalized(t, const SettingsScreen(), container: c, theme: KivoTheme.dark());
    await t.pumpAndSettle();

    await _search(t, _l10n.settingsInterfaceOverlayCorner);
    await t.tap(find.byKey(const ValueKey('settings-hit-${SettingIds.overlayCorner}')));

    expect(await _peakFlash(t, SettingIds.showOverlay), greaterThan(0.1));
    await t.pumpAndSettle();
    expect(find.byType(InterfaceSettingsSection), findsOneWidget);
  });

  testWidgets('the typed words are lit in the result title', (t) async {
    final c = await _container((s) => s);
    await pumpLocalized(t, const SettingsScreen(), container: c, theme: KivoTheme.dark());
    await t.pumpAndSettle();

    await _search(t, 'acento');
    final rich = find.descendant(
        of: find.byKey(const ValueKey('settings-hit-${SettingIds.accentColor}')),
        matching: find.byType(RichText));
    final spans = <String>[];
    (t.widget<RichText>(rich.first).text as TextSpan).visitChildren((s) {
      if (s is TextSpan && s.style?.fontWeight == FontWeight.w800) spans.add(s.text!);
      return true;
    });
    expect(spans, ['acento']);
  });

  testWidgets('no match says so, with what was typed', (t) async {
    final c = await _container((s) => s);
    await pumpLocalized(t, const SettingsScreen(), container: c, theme: KivoTheme.dark());
    await t.pumpAndSettle();

    await _search(t, 'zzzz');
    expect(find.text(_l10n.settingsSearchEmpty('zzzz')), findsOneWidget);
  });

  testWidgets('the hidden Vault never appears in results', (t) async {
    final c = await _container((s) => s.copyWith(vaultEntranceHidden: true));
    await pumpLocalized(t, const SettingsScreen(), container: c, theme: KivoTheme.dark());
    await t.pumpAndSettle();

    await _search(t, 'vault');
    expect(find.byKey(const ValueKey('settings-hit-vault')), findsNothing);
    expect(find.text('Vault'), findsNothing);
  });

  testWidgets('with text, the ✕ only clears it: the field keeps focus, so the keyboard stays up',
      (t) async {
    final c = await _container((s) => s);
    await pumpLocalized(t, const SettingsScreen(), container: c, theme: KivoTheme.dark());
    await t.pumpAndSettle();

    await _search(t, 'tema');
    await t.tap(find.byTooltip(_l10n.settingsSearchClear));
    await t.pumpAndSettle();

    final field = find.byKey(const ValueKey('settings-search-field'));
    expect(field, findsOneWidget, reason: 'the search stays open');
    expect(t.widget<TextField>(field).controller!.text, '');
    expect(c.read(settingsSearchQueryProvider), '');
    expect(t.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(t.testTextInput.isVisible, isTrue, reason: 'keyboard still up');

    // Empty now, so the same ✕ closes the search.
    await t.tap(find.byTooltip(_l10n.settingsSearchClose));
    await t.pumpAndSettle();
    expect(c.read(settingsSearchActiveProvider), isFalse);
  });

  testWidgets('closing the search clears it and brings the section list back', (t) async {
    final c = await _container((s) => s);
    await pumpLocalized(t, const SettingsScreen(), container: c, theme: KivoTheme.dark());
    await t.pumpAndSettle();

    await _search(t, 'tema');
    expect(find.text(_l10n.settingsAboutTitle), findsNothing);
    await t.tap(find.byTooltip(_l10n.settingsSearchClear));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip(_l10n.settingsSearchClose));
    await t.pumpAndSettle();

    expect(c.read(settingsSearchActiveProvider), isFalse);
    expect(c.read(settingsSearchQueryProvider), '');
    expect(find.text(_l10n.settingsAboutTitle), findsOneWidget);

    // Reopened, it starts empty rather than with the old text.
    await t.tap(find.byTooltip(_l10n.settingsSearchTooltip));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byKey(const ValueKey('settings-search-field'))).controller!.text, '');
  });
}
