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

  test('a video with nothing remembered loads no file and zeroes the offset',
      () async {
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

    expect(engine.subtitleDelays, [0.0]);
    expect(engine.externalSubtitles, isEmpty);
  });

  // mpv's sub-delay is an ordinary option on a process-lifetime singleton
  // Player: loadfile does not reset it. A video with no stored offset has to
  // clear the previous one itself, or it plays desynced while the HUD (which
  // did rebuild to 0) insists nothing is wrong.
  test('the previous video\'s offset does not leak onto the next one',
      () async {
    final engine = FakePlaybackEngine();
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: 500));

    applyDefaultTracks(
      engine: engine,
      settings: KivoSettings.defaults(),
      session: _session(),
      subtitleFinder: FakeSubtitleFinder(),
      subtitlePrefs: store,
    );
    await _drainTrackStreams(engine);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    applyDefaultTracks(
      engine: engine,
      settings: KivoSettings.defaults(),
      session: const VideoSession(
          playbackPath: '/v/ep2.mkv',
          displayName: 'ep2.mkv',
          queue: ['/v/ep2.mkv'],
          index: 0),
      subtitleFinder: FakeSubtitleFinder(),
      subtitlePrefs: store,
    );
    await _drainTrackStreams(engine);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(engine.subtitleDelays, [0.5, 0.0]);
  });

  test('a corrupted prefs record still clears the previous offset', () async {
    final engine = FakePlaybackEngine();
    applyDefaultTracks(
      engine: engine,
      settings: KivoSettings.defaults(),
      session: _session(),
      subtitleFinder: FakeSubtitleFinder(),
      subtitlePrefs: _ThrowingSubtitlePrefsStore(),
    );
    await _drainTrackStreams(engine);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(engine.subtitleDelays, [0.0]);
  });
}

/// A Hive record that cannot be decoded: [forKey] throwing must not escape
/// applyDefaultTracks' fire-and-forget IIFE (there is no zone handler for it),
/// and must not skip the delay reset either.
class _ThrowingSubtitlePrefsStore implements SubtitlePrefsStore {
  @override
  VideoSubtitlePrefs? forKey(String key) => throw StateError('corrupt record');
  @override
  Future<void> put(String key, VideoSubtitlePrefs prefs) async {}
  @override
  Future<void> remove(String key) async {}
  @override
  Future<void> rename(String oldKey, String newKey) async {}
}
