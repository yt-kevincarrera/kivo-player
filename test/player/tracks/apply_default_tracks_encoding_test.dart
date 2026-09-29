import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/platform/interfaces/subtitle_transcoder.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/apply_default_tracks.dart';
import 'package:kivo_player/player/tracks/subtitle_loader.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import '../../fakes/fakes.dart';

VideoSession _session() => const VideoSession(
    playbackPath: '/v/ep1.mkv',
    displayName: 'ep1.mkv',
    queue: ['/v/ep1.mkv'],
    index: 0,
    folder: 'Series');

Future<void> _drain(FakePlaybackEngine engine) async {
  engine.emitAudioTracks(const []);
  await Future<void>.delayed(Duration.zero);
  engine.emitSubtitleTracks(const []);
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

void main() {
  test('a remembered subtitle is re-read in the encoding chosen for the video',
      () async {
    final engine = FakePlaybackEngine();
    final store = InMemoryTrackPrefsStore();
    await store.put(
        'ep1.mkv',
        const VideoTrackPrefs(
            subtitlePath: '/subs/ep1.srt', subtitleEncoding: 'windows-1251'));
    final transcoder = FakeSubtitleTranscoder()
      ..answer = (uri, enc) => PreparedSubtitle(
          uri: '/cache/ep1.srt', encoding: enc, detected: enc == null);
    ActiveExternalSubtitle? active;
    final loader = SubtitleLoader(
        engine: engine,
        transcoder: () => transcoder,
        prefs: store,
        readActive: () => active,
        writeActive: (v) => active = v);

    applyDefaultTracks(
      engine: engine,
      subtitleLoader: loader,
      settings: KivoSettings.defaults(),
      session: _session(),
      subtitleFinder: FakeSubtitleFinder(),
      subtitlePrefs: store,
    );
    await _drain(engine);

    expect(transcoder.calls.single, ('/subs/ep1.srt', 'ep1.srt', 'windows-1251'));
    expect(engine.externalSubtitles.single.$1, '/cache/ep1.srt');
    expect(active!.encoding, 'windows-1251');
  });

  test("opening the next video drops the previous one's active subtitle", () {
    final engine = FakePlaybackEngine();
    ActiveExternalSubtitle? active = const ActiveExternalSubtitle(
        resumeKey: 'old.mkv',
        sourceUri: '/subs/old.srt',
        title: null,
        encoding: 'UTF-8',
        detected: true,
        binary: false);
    final loader = SubtitleLoader(
        engine: engine,
        transcoder: FakeSubtitleTranscoder.new,
        prefs: InMemoryTrackPrefsStore(),
        readActive: () => active,
        writeActive: (v) => active = v);

    applyDefaultTracks(
      engine: engine,
      subtitleLoader: loader,
      settings: KivoSettings.defaults(),
      session: _session(),
      subtitleFinder: FakeSubtitleFinder(),
      subtitlePrefs: InMemoryTrackPrefsStore(),
    );
    expect(active, isNull, reason: 'cleared synchronously, before any await');
    engine.emitAudioTracks(const []);
  });
}
