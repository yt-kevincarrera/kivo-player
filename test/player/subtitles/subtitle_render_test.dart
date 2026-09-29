import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/subtitles/subtitle_render.dart';

SubtitleDrawer _d(String? codec,
        {bool hasTrack = true, bool respect = true, bool fonts = true}) =>
    drawerFor(
        hasTrack: hasTrack,
        codec: codec,
        respectAssStyle: respect,
        fontsReady: fonts);

void main() {
  test('no track, nobody draws', () {
    expect(_d('subrip', hasTrack: false), SubtitleDrawer.none);
  });

  test('plain text is always Kivo', () {
    for (final c in ['subrip', 'webvtt', 'mov_text', 'text']) {
      expect(_d(c), SubtitleDrawer.kivo, reason: c);
    }
  });

  test('pictures are always mpv — the only way they show at all', () {
    for (final c in bitmapSubtitleCodecs) {
      expect(_d(c, respect: false, fonts: false), SubtitleDrawer.mpv,
          reason: c);
    }
  });

  test('ASS is mpv when its style is respected and libass has a font', () {
    expect(_d('ass'), SubtitleDrawer.mpv);
    expect(_d('ssa'), SubtitleDrawer.mpv);
  });

  test('ASS falls back to Kivo when the user opts out', () {
    expect(_d('ass', respect: false), SubtitleDrawer.kivo);
  });

  test('ASS falls back to Kivo when no font could be prepared', () {
    expect(_d('ass', fonts: false), SubtitleDrawer.kivo,
        reason: 'boxes instead of letters is the worse failure');
  });

  test('an unknown codec with a track is treated as text', () {
    expect(_d(null), SubtitleDrawer.kivo);
  });
}
