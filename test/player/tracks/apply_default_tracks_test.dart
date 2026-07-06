import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/apply_default_tracks.dart';
import 'package:kivo_player/platform/interfaces/subtitle_finder.dart';
import '../../fakes/fakes.dart';

class _NoSubs implements SubtitleFinder {
  @override
  Future<List<ExternalSubtitle>> findNear(String folder) async => const [];
}

void main() {
  test('applies the preferred audio track when it matches', () async {
    final e = FakePlaybackEngine();
    addTearDown(e.dispose);
    const session = VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0);
    applyDefaultTracks(
        engine: e,
        settings: KivoSettings.defaults().copyWith(preferredAudioLanguage: 'es'),
        session: session,
        subtitleFinder: _NoSubs());
    // Emit tracks so the .first calls resolve (no 2s timeout timer left pending).
    // A pump is needed between the two emissions: the subtitle stream's
    // `.first` only subscribes after the audio pick's `await setAudioTrack`
    // resolves, one microtask later than the synchronous body above — so
    // emitting subtitles in the same sync block as audio would be missed by
    // a not-yet-subscribed listener (broadcast streams don't replay).
    e.emitAudioTracks(const [
      MediaTrack(id: '1', title: 'EN', language: 'en'),
      MediaTrack(id: '2', title: 'ES', language: 'es'),
    ]);
    await Future<void>.delayed(Duration.zero);
    e.emitSubtitleTracks(const []);
    await Future<void>.delayed(Duration.zero);
    expect(e.currentAudioTrackId, '2'); // the 'es' pick
  });
}
