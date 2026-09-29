import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/subtitle_transcoder.dart';
import 'package:kivo_player/player/tracks/subtitle_loader.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import '../../fakes/fakes.dart';

class _SlowTranscoder extends FakeSubtitleTranscoder {
  final gate = Completer<void>();
  @override
  Future<PreparedSubtitle> prepare(String uri,
      {String? name, String? encoding}) async {
    await gate.future;
    return super.prepare(uri, name: name, encoding: encoding);
  }
}

class _RejectingTranscoder extends FakeSubtitleTranscoder {
  @override
  Future<PreparedSubtitle> prepare(String uri,
      {String? name, String? encoding}) async {
    calls.add((uri, name, encoding));
    if (encoding != null) throw StateError('unsupported charset $encoding');
    return PreparedSubtitle(uri: uri, encoding: 'UTF-8', detected: true);
  }
}

void main() {
  test("a load still in flight when the video changes never lands", () async {
    final engine = FakePlaybackEngine();
    final transcoder = _SlowTranscoder();
    ActiveExternalSubtitle? active;
    final loader = SubtitleLoader(
        engine: engine,
        transcoder: () => transcoder,
        prefs: InMemoryTrackPrefsStore(),
        readActive: () => active,
        writeActive: (v) => active = v);

    final late = loader.load('/subs/a.srt', resumeKey: 'a.mkv');
    loader.clear(); // video B opened
    transcoder.gate.complete();
    await late;

    expect(engine.externalSubtitles, isEmpty);
    expect(active, isNull);
  });

  test('a chosen charset the device cannot decode is forgotten, then detected',
      () async {
    final engine = FakePlaybackEngine();
    final prefs = InMemoryTrackPrefsStore();
    await prefs.put('a.mkv',
        const VideoTrackPrefs(subtitleEncoding: 'x-bogus', subtitleDelayMs: 90));
    final transcoder = _RejectingTranscoder();
    ActiveExternalSubtitle? active;
    final loader = SubtitleLoader(
        engine: engine,
        transcoder: () => transcoder,
        prefs: prefs,
        readActive: () => active,
        writeActive: (v) => active = v);

    await loader.load('/subs/a.srt', resumeKey: 'a.mkv');

    expect(transcoder.calls.map((c) => c.$3), ['x-bogus', null]);
    expect(prefs.forKey('a.mkv')!.subtitleEncoding, isNull);
    expect(prefs.forKey('a.mkv')!.subtitleDelayMs, 90);
    expect(active!.detected, isTrue);
    expect(engine.externalSubtitles.single.$1, '/subs/a.srt');
  });
}
