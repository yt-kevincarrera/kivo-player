import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/apply_default_tracks.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/player/tracks/track_selection.dart';
import '../../fakes/fakes.dart';

const _es = MediaTrack(id: '1', language: 'es', codec: 'subrip');
const _en = MediaTrack(id: '2', language: 'en', codec: 'subrip');
const _enPgs = MediaTrack(id: '3', language: 'en', codec: 'hdmv_pgs_subtitle');

Future<void> _open(FakePlaybackEngine engine, KivoSettings settings,
    List<MediaTrack> subs) async {
  applyDefaultTracks(
    engine: engine,
    subtitleLoader: rawSubtitleLoader(engine),
    applyAudio: () async {},
    settings: settings,
    session: const VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0),
    subtitleFinder: FakeSubtitleFinder(),
    subtitlePrefs: InMemoryTrackPrefsStore(),
  );
  engine.emitAudioTracks(const []);
  await Future<void>.delayed(Duration.zero);
  engine.emitSubtitleTracks(subs);
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

void main() {
  group('selectSecondarySubtitleTrack', () {
    test('picks the remembered language, never the primary', () {
      expect(
          selectSecondarySubtitleTrack(
              tracks: [_es, _en], language: 'en', primaryId: '1'),
          _en);
      expect(
          selectSecondarySubtitleTrack(
              tracks: [_en], language: 'en', primaryId: '2'),
          isNull);
    });

    test('never a picture subtitle', () {
      expect(
          selectSecondarySubtitleTrack(
              tracks: [_es, _enPgs], language: 'en', primaryId: '1'),
          isNull);
    });

    test('no remembered language, no secondary', () {
      expect(
          selectSecondarySubtitleTrack(
              tracks: [_es, _en], language: null, primaryId: '1'),
          isNull);
    });
  });

  group('on open', () {
    test('the remembered secondary is selected', () async {
      final engine = FakePlaybackEngine();
      await _open(
          engine,
          KivoSettings.defaults().copyWith(
              preferredSubtitleLanguage: 'es', secondarySubtitleLanguage: 'en'),
          [_es, _en]);
      expect(engine.secondarySubtitleWrites, ['2']);
    });

    // secondary-sid survives loadfile: a video with nothing to pick must turn
    // it off, or the previous video's id is tried on this one.
    test('a video without that language writes it off, unconditionally',
        () async {
      final engine = FakePlaybackEngine();
      await _open(engine, KivoSettings.defaults(), [_es]);
      expect(engine.secondarySubtitleWrites, [null]);
    });

    test('subtitles off means no secondary either', () async {
      final engine = FakePlaybackEngine();
      await _open(
          engine,
          KivoSettings.defaults().copyWith(
              subtitlesEnabledByDefault: false, secondarySubtitleLanguage: 'en'),
          [_es, _en]);
      expect(engine.secondarySubtitleWrites, [null]);
    });
  });
}
