import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/subtitles/secondary_subtitle.dart';

void main() {
  const es = MediaTrack(id: '1', language: 'es', codec: 'subrip');
  const extEn = MediaTrack(id: '2', language: 'en', codec: 'subrip');
  const pgs = MediaTrack(id: '3', language: 'fr', codec: 'hdmv_pgs_subtitle');

  test('the primary, by id or by mpv number, is never a candidate', () {
    // An external primary: media_kit says 'content://…', mpv lists it as '2'.
    const primary = MediaTrack(id: 'content://media/7', language: 'en');
    expect(
        secondaryCandidates([es, extEn, pgs], primary, primaryMpvId: '2'),
        [es]);
  });

  test('pictures are never candidates', () {
    expect(secondaryCandidates([es, pgs], null), [es]);
  });
}
