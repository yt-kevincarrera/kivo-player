import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/subtitles/subtitle_render.dart';
import 'package:kivo_player/player/subtitles/subtitle_render_controller.dart';
import 'package:kivo_player/ui/player/state/controls_insets.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/player/subtitles/subtitle_overlay.dart';
import 'package:kivo_player/ui/player/subtitles/subtitle_text.dart';
import 'package:kivo_player/ui/player/tracks/track_sync_hud.dart';
import '../../../fakes/fakes.dart';
import '../../../helpers/pump_app.dart';

class _H {
  _H(this.c, this.engine);
  final ProviderContainer c;
  final FakePlaybackEngine engine;
}

Future<_H> _pump(WidgetTester tester,
    {KivoSettings Function(KivoSettings)? tweak,
    SubtitleDrawer drawer = SubtitleDrawer.kivo}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  if (tweak != null) await s.update(tweak(s.current));
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
  ]);
  addTearDown(c.dispose);
  c.read(subtitleDrawerProvider.notifier).state = drawer;
  await tester.binding.setSurfaceSize(const Size(720, 360));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpLocalized(tester, const SizedBox.expand(child: SubtitleOverlay()),
      container: c);
  await tester.pump();
  return _H(c, engine);
}

void main() {
  testWidgets('Kivo draws the text mpv reports', (tester) async {
    final h = await _pump(tester);
    h.engine.emitSubtitleText('Hola, ¿qué tal?');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('subtitle-primary')), findsOneWidget);
    expect(find.text('Hola, ¿qué tal?'), findsWidgets);
  });

  testWidgets('nothing of Kivo\'s while mpv draws the subtitle', (tester) async {
    final h = await _pump(tester, drawer: SubtitleDrawer.mpv);
    h.engine.emitSubtitleText('Styled ASS line');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('subtitle-primary')), findsNothing);
  });

  // mpv reports the text as unavailable once the secondary is off, and
  // media_kit keeps the last cue: the overlay must not draw it.
  testWidgets('a stale secondary cue is not drawn once it is switched off',
      (tester) async {
    final h = await _pump(tester);
    h.engine.secondarySubtitleTrackId = null;
    h.engine.emitSubtitleText('Hola', 'Hello (stale)');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('subtitle-secondary')), findsNothing);
  });

  testWidgets('the secondary shows at the top, whoever draws the primary',
      (tester) async {
    final h = await _pump(tester, drawer: SubtitleDrawer.mpv);
    h.engine.secondarySubtitleTrackId = '2';
    h.engine.emitSubtitleText('', 'Hello, how are you?');
    await tester.pump();
    await tester.pump();
    final secondary = find.byKey(const Key('subtitle-secondary'));
    expect(secondary, findsOneWidget);
    expect(tester.getTopLeft(secondary).dy, lessThan(360 / 2));
  });

  testWidgets('the configured bottom margin places the line', (tester) async {
    final h = await _pump(tester,
        tweak: (s) => s.copyWith(subtitleBottomMargin: 20));
    h.engine.emitSubtitleText('Line');
    await tester.pumpAndSettle();
    final bottom = tester.getBottomLeft(find.byKey(const Key('subtitle-primary'))).dy;
    // 4 px of the (always present, so nothing jumps) drag frame padding.
    expect(bottom, closeTo(360 - 360 * 0.20 - 4, 1.0));
  });

  testWidgets('no lift under the sync panel: the bars are not drawn there',
      (tester) async {
    final h = await _pump(tester);
    h.engine.emitSubtitleText('Line');
    await tester.pumpAndSettle();
    final before =
        tester.getBottomLeft(find.byKey(const Key('subtitle-primary'))).dy;
    h.c.read(controlsBottomInsetProvider.notifier).state = 120;
    h.c.read(syncHudProvider.notifier).show(SyncTarget.subtitles);
    h.c.read(controlsVisibleProvider.notifier).show();
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.byKey(const Key('subtitle-primary'))).dy,
        before);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('it steps above the bottom controls while they show',
      (tester) async {
    final h = await _pump(tester);
    h.engine.emitSubtitleText('Line');
    await tester.pumpAndSettle();
    final before =
        tester.getBottomLeft(find.byKey(const Key('subtitle-primary'))).dy;

    h.c.read(controlsBottomInsetProvider.notifier).state = 120;
    h.c.read(controlsVisibleProvider.notifier).show();
    await tester.pumpAndSettle();
    final after =
        tester.getBottomLeft(find.byKey(const Key('subtitle-primary'))).dy;
    expect(before - after, closeTo(120, 1.0));
    await tester.pump(const Duration(seconds: 6)); // the controls auto-hide timer
  });

  testWidgets('empty text draws nothing at all', (tester) async {
    final h = await _pump(tester);
    h.engine.emitSubtitleText('   ');
    await tester.pump();
    await tester.pump();
    expect(find.byType(SubtitleText), findsNothing);
  });

  group('SubtitleText', () {
    Future<void> render(WidgetTester t, KivoSettings s) =>
        t.pumpWidget(MaterialApp(
            home: Center(child: SubtitleText(text: 'Texto', settings: s))));

    List<Text> texts(WidgetTester t) =>
        t.widgetList<Text>(find.text('Texto')).toList();

    testWidgets('an outline adds a stroke layer under the fill', (t) async {
      await render(t, KivoSettings.defaults());
      final layers = texts(t);
      expect(layers, hasLength(2));
      expect(layers.first.style!.foreground!.style, PaintingStyle.stroke);
      expect(layers.first.style!.foreground!.strokeWidth, 4.0);
    });

    testWidgets('no outline, a single layer', (t) async {
      await render(t, KivoSettings.defaults().copyWith(subtitleOutlineWidth: 0));
      expect(texts(t), hasLength(1));
    });

    testWidgets('bold, font and shadow come from the settings', (t) async {
      await render(
          t,
          KivoSettings.defaults().copyWith(
              subtitleBold: true,
              subtitleFontFamily: 'serif',
              subtitleShadow: false,
              subtitleOutlineWidth: 0));
      final style = texts(t).single.style!;
      expect(style.fontWeight, FontWeight.w800);
      expect(style.fontFamily, 'serif');
      expect(style.shadows, isNull);
    });

    testWidgets('a background only when it is not transparent', (t) async {
      await render(t, KivoSettings.defaults());
      expect(find.byType(DecoratedBox), findsNothing);
      await render(t,
          KivoSettings.defaults().copyWith(subtitleBackgroundColor: 0xAA000000));
      expect(find.byType(DecoratedBox), findsOneWidget);
    });
  });
}
