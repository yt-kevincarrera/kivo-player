import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/subtitle_transcoder_provider.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/subtitles/subtitle_render.dart';
import 'package:kivo_player/player/subtitles/subtitle_render_controller.dart';

import '../../fakes/fakes.dart';

class _H {
  _H(this.c, this.engine, this.transcoder);
  final ProviderContainer c;
  final FakePlaybackEngine engine;
  final FakeSubtitleTranscoder transcoder;
  SubtitleRenderController get ctl => c.read(subtitleRenderProvider);
  SubtitleDrawer get drawer => c.read(subtitleDrawerProvider);

  Future<void> select(String? codec) async {
    engine.currentSubtitleTrackValue =
        codec == null ? null : MediaTrack(id: '3', codec: codec);
    engine.subtitleCodecValue = codec;
    await ctl.refresh();
  }
}

Future<_H> _harness(
    {KivoSettings Function(KivoSettings)? tweak, bool font = true}) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  if (tweak != null) await svc.update(tweak(svc.current));
  final engine = FakePlaybackEngine();
  final transcoder = FakeSubtitleTranscoder();
  if (!font) transcoder.font = null;
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    playbackEngineProvider.overrideWithValue(engine),
    subtitleTranscoderProvider.overrideWithValue(transcoder),
  ]);
  addTearDown(c.dispose);
  final h = _H(c, engine, transcoder);
  await h.ctl.start();
  return h;
}

void main() {
  test('start hands libass the system font', () async {
    final h = await _harness();
    expect(h.engine.subtitleFonts?.family, 'Roboto');
    expect(h.engine.subtitleRenderingWrites, [false],
        reason: 'no track yet: mpv draws nothing');
  });

  test('a text track is Kivo\'s, a picture track is mpv\'s', () async {
    final h = await _harness();
    await h.select('subrip');
    expect(h.drawer, SubtitleDrawer.kivo);
    await h.select('hdmv_pgs_subtitle');
    expect(h.drawer, SubtitleDrawer.mpv);
    expect(h.engine.subtitleRenderingWrites, [false, true]);
  });

  test('sub-visibility is only written when it changes', () async {
    final h = await _harness();
    await h.select('subrip');
    await h.select('webvtt');
    await h.select(null);
    expect(h.engine.subtitleRenderingWrites, [false]);
  });

  test('ASS goes to mpv, or to Kivo when the user turns style off', () async {
    final h = await _harness();
    await h.select('ass');
    expect(h.drawer, SubtitleDrawer.mpv);
    await h.c.read(settingsProvider.notifier).set(
        h.c.read(settingsProvider).copyWith(subtitleRespectAss: false));
    await Future<void>.delayed(Duration.zero);
    await h.ctl.refresh();
    expect(h.drawer, SubtitleDrawer.kivo);
    expect(h.engine.subtitleRenderingWrites.last, false);
  });

  test('without a font for libass, ASS stays with Kivo', () async {
    final h = await _harness(font: false);
    expect(h.engine.subtitleFonts, isNull);
    await h.select('ass');
    expect(h.drawer, SubtitleDrawer.kivo);
  });

  test('turning subtitles off means nobody draws', () async {
    final h = await _harness();
    await h.select('hdmv_pgs_subtitle');
    await h.select(null);
    expect(h.drawer, SubtitleDrawer.none);
    expect(h.engine.subtitleRenderingWrites.last, false);
  });
}
