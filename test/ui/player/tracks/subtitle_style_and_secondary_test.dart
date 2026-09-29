import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/subtitles/subtitle_text.dart';
import 'package:kivo_player/ui/player/tracks/track_picker.dart';
import '../../../fakes/fakes.dart';
import '../../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

const _es = MediaTrack(id: '1', title: 'Español', language: 'es', codec: 'subrip');
const _en = MediaTrack(id: '2', title: 'English', language: 'en', codec: 'subrip');
const _pgs =
    MediaTrack(id: '3', title: 'PGS', language: 'fr', codec: 'hdmv_pgs_subtitle');

class _H {
  _H(this.c, this.engine);
  final ProviderContainer c;
  final FakePlaybackEngine engine;
}

Future<_H> _open(WidgetTester tester,
    {bool style = false, KivoSettings Function(KivoSettings)? tweak}) async {
  final engine = FakePlaybackEngine()
    ..currentSubtitleTrackValue = _es
    ..subtitleTracksValue = const [_es, _en, _pgs];
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  if (tweak != null) await s.update(tweak(s.current));
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(const VideoSession(
      playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
  await tester.binding.setSurfaceSize(const Size(420, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpLocalized(
    tester,
    Scaffold(
      body: Center(
        child: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () => showSubtitlePicker(context, ref),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    container: c,
    theme: KivoTheme.dark(),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (style) {
    await tester.tap(find.text(_l10n.playerTracksStyleTabLabel));
    await tester.pumpAndSettle();
  }
  return _H(c, engine);
}

Future<void> _reach(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).last);
  await tester.pumpAndSettle();
}

void main() {
  group('Segundo subtítulo', () {
    testWidgets('lists text tracks other than the primary, never pictures',
        (tester) async {
      await _open(tester);
      expect(find.text(_l10n.playerTracksSectionSecondary.toUpperCase()),
          findsOneWidget);
      expect(find.text(_l10n.playerTracksSecondaryOff), findsOneWidget);
      expect(find.text(_l10n.playerTracksSecondaryHint), findsOneWidget,
          reason: 'only English qualifies: Español is primary, PGS a picture');
    });

    testWidgets('picking one shows it and remembers its language',
        (tester) async {
      final h = await _open(tester);
      await _reach(tester, find.text(_l10n.playerTracksSecondaryHint));
      await tester.tap(find.text(_l10n.playerTracksSecondaryHint));
      await tester.pumpAndSettle();
      expect(h.engine.secondarySubtitleWrites.last, '2');
      expect(h.c.read(settingsProvider).secondarySubtitleLanguage, 'en');
    });

    testWidgets('Ninguno turns it off and forgets the language', (tester) async {
      final h = await _open(tester,
          tweak: (s) => s.copyWith(secondarySubtitleLanguage: 'en'));
      await _reach(tester, find.text(_l10n.playerTracksSecondaryOff));
      await tester.tap(find.text(_l10n.playerTracksSecondaryOff));
      await tester.pumpAndSettle();
      expect(h.engine.secondarySubtitleWrites.last, isNull);
      expect(h.c.read(settingsProvider).secondarySubtitleLanguage, isNull);
    });
  });

  group('Segundo subtítulo, with the primary', () {
    testWidgets('turning subtitles off takes the secondary with them',
        (tester) async {
      final h = await _open(tester);
      h.engine.secondarySubtitleTrackId = '2';
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(h.engine.secondarySubtitleWrites.last, isNull);
    });

    // mpv refuses a track already held as the secondary.
    testWidgets('picking the secondary track as primary frees it first',
        (tester) async {
      final h = await _open(tester);
      h.engine.secondarySubtitleTrackId = '2';
      await tester.tap(find.text('English').first);
      await tester.pumpAndSettle();
      expect(h.engine.secondarySubtitleWrites.last, isNull);
      expect(h.engine.currentSubtitleTrackId, '2');
    });
  });

  group('Estilo', () {
    testWidgets('the preview is the overlay\'s own widget', (tester) async {
      await _open(tester, style: true);
      expect(find.byType(SubtitleText), findsOneWidget);
    });

    testWidgets('shadow, bold and ASS switches persist', (tester) async {
      final h = await _open(tester, style: true);
      Future<void> flip(String label) async {
        await _reach(tester, find.text(label));
        await tester.tap(find.descendant(
            of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
            matching: find.byType(Switch)));
        await tester.pumpAndSettle();
      }

      await flip(_l10n.playerTracksShadowLabel);
      await flip(_l10n.playerTracksBoldLabel);
      await flip(_l10n.playerTracksRespectAss);
      final s = h.c.read(settingsProvider);
      expect(s.subtitleShadow, isFalse);
      expect(s.subtitleBold, isTrue);
      expect(s.subtitleRespectAss, isFalse);
    });

    testWidgets('a font chip picks the family', (tester) async {
      final h = await _open(tester, style: true);
      await _reach(tester, find.text(_l10n.playerTracksFontSerif));
      await tester.tap(find.text(_l10n.playerTracksFontSerif));
      await tester.pumpAndSettle();
      expect(h.c.read(settingsProvider).subtitleFontFamily, 'serif');
    });

    testWidgets('outline color only shows with an outline', (tester) async {
      await _open(tester,
          style: true, tweak: (s) => s.copyWith(subtitleOutlineWidth: 0));
      await _reach(tester, find.text(_l10n.playerTracksOutlineNone));
      expect(find.text(_l10n.playerTracksOutlineNone), findsOneWidget);
      expect(find.text(_l10n.playerTracksOutlineColorLabel.toUpperCase()),
          findsNothing);
    });

    testWidgets('Restablecer brings every style setting back', (tester) async {
      final h = await _open(tester,
          style: true,
          tweak: (s) => s.copyWith(
              subtitleBold: true,
              subtitleFontFamily: 'mono',
              subtitleBottomMargin: 30,
              subtitleRespectAss: false));
      await _reach(tester, find.text(_l10n.playerTracksResetStyleAction));
      await tester.tap(find.text(_l10n.playerTracksResetStyleAction));
      await tester.pumpAndSettle();
      final s = h.c.read(settingsProvider);
      final d = KivoSettings.defaults();
      expect(s.subtitleBold, d.subtitleBold);
      expect(s.subtitleFontFamily, d.subtitleFontFamily);
      expect(s.subtitleBottomMargin, d.subtitleBottomMargin);
      expect(s.subtitleRespectAss, d.subtitleRespectAss);
    });
  });
}
