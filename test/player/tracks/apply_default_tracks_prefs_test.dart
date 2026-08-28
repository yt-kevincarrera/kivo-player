import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/apply_default_tracks.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import '../../fakes/fakes.dart';

VideoSession _session() => const VideoSession(
    playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0);

// applyDefaultTracks awaits audioTracksStream.first and subtitleTracksStream
// .first, each with a real 2-second fallback timeout when the stream stays
// silent. Emitting empty lists (as apply_default_tracks_test.dart already
// does) lets those two awaits resolve via a real stream event instead of the
// 2s timers, so the prefs section below runs within the test's short delay
// instead of the suite needing ~4s of real wall-clock time per case.
Future<void> _drainTrackStreams(FakePlaybackEngine engine) async {
  engine.emitAudioTracks(const []);
  await Future<void>.delayed(Duration.zero);
  engine.emitSubtitleTracks(const []);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('a remembered offset is applied on open', () async {
    final engine = FakePlaybackEngine();
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: -750));

    applyDefaultTracks(
      engine: engine,
      settings: KivoSettings.defaults(),
      session: _session(),
      subtitleFinder: FakeSubtitleFinder(),
      subtitlePrefs: store,
    );
    await _drainTrackStreams(engine);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(engine.subtitleDelays, [-0.75]);
  });

  test('a remembered subtitle file is loaded before the offset', () async {
    final engine = FakePlaybackEngine();
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv',
        const VideoSubtitlePrefs(delayMs: 500, subtitlePath: '/subs/ep1.srt'));

    applyDefaultTracks(
      engine: engine,
      settings: KivoSettings.defaults(),
      session: _session(),
      subtitleFinder: FakeSubtitleFinder(),
      subtitlePrefs: store,
    );
    await _drainTrackStreams(engine);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(engine.externalSubtitles.single, '/subs/ep1.srt');
    expect(engine.subtitleDelays, [0.5]);
  });

  test('a video with nothing remembered touches neither', () async {
    final engine = FakePlaybackEngine();
    applyDefaultTracks(
      engine: engine,
      settings: KivoSettings.defaults(),
      session: _session(),
      subtitleFinder: FakeSubtitleFinder(),
      subtitlePrefs: InMemorySubtitlePrefsStore(),
    );
    await _drainTrackStreams(engine);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(engine.subtitleDelays, isEmpty);
    expect(engine.externalSubtitles, isEmpty);
  });
}
