import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/subtitle_transcoder.dart';
import 'package:kivo_player/player/tracks/subtitle_loader.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import '../../fakes/fakes.dart';

class _H {
  final engine = FakePlaybackEngine();
  final transcoder = FakeSubtitleTranscoder();
  final prefs = InMemoryTrackPrefsStore();
  ActiveExternalSubtitle? active;
  late final loader = SubtitleLoader(
    engine: engine,
    transcoder: () => transcoder,
    prefs: prefs,
    readActive: () => active,
    writeActive: (v) => active = v,
  );
}

void main() {
  test('mpv gets the converted copy, the picker gets the original', () async {
    final h = _H();
    h.transcoder.answer = (uri, enc) => const PreparedSubtitle(
        uri: '/cache/abc.srt', encoding: 'windows-1251', detected: true);

    await h.loader.load('content://media/external/file/7',
        title: 'ep1.ru.srt', resumeKey: 'ep1.mkv');

    expect(h.engine.externalSubtitles.single, ('/cache/abc.srt', 'ep1.ru.srt'));
    expect(h.transcoder.calls.single,
        ('content://media/external/file/7', 'ep1.ru.srt', null));
    expect(h.active!.sourceUri, 'content://media/external/file/7');
    expect(h.active!.encoding, 'windows-1251');
    expect(h.active!.detected, isTrue);
  });

  test("the video's chosen encoding is what the transcoder is asked for",
      () async {
    final h = _H();
    await h.prefs.put('ep1.mkv', const VideoTrackPrefs(subtitleEncoding: 'GBK'));
    await h.loader.load('/subs/ep1.srt', resumeKey: 'ep1.mkv');
    expect(h.transcoder.calls.single.$3, 'GBK');
    expect(h.active!.detected, isFalse);
  });

  test('a transcoder failure still loads the file as-is', () async {
    final h = _H();
    h.transcoder.error = StateError('channel down');
    await h.loader.load('/subs/ep1.srt', title: 'ep1.srt', resumeKey: 'ep1.mkv');
    expect(h.engine.externalSubtitles.single, ('/subs/ep1.srt', 'ep1.srt'));
    expect(h.active!.encoding, isNull);
    expect(h.active!.binary, isFalse,
        reason: 'unknown is not binary: the user may still pick an encoding');
  });

  test('a binary subtitle is marked so the encoding card stays away', () async {
    final h = _H();
    h.transcoder.answer = (uri, enc) =>
        PreparedSubtitle(uri: uri, encoding: null, detected: false);
    await h.loader.load('/subs/movie.sub', resumeKey: 'movie.mkv');
    expect(h.active!.binary, isTrue);
  });

  test('reloading in another encoding remembers it and replaces the track',
      () async {
    final h = _H();
    await h.prefs.put('ep1.mkv', const VideoTrackPrefs(subtitleDelayMs: 250));
    await h.loader.load('content://x/7', title: 'ep1.srt', resumeKey: 'ep1.mkv');

    await h.loader.reloadWithEncoding('windows-1253');

    expect(h.prefs.forKey('ep1.mkv')!.subtitleEncoding, 'windows-1253');
    expect(h.prefs.forKey('ep1.mkv')!.subtitleDelayMs, 250,
        reason: 'the offset for this video survives');
    expect(h.transcoder.calls.last, ('content://x/7', 'ep1.srt', 'windows-1253'));
    expect(h.engine.subtitleReplaceCount, 1,
        reason: 'no duplicate track per attempt');
    expect(h.active!.encoding, 'windows-1253');
  });

  test('back to automatic clears the stored choice', () async {
    final h = _H();
    await h.prefs.put('ep1.mkv', const VideoTrackPrefs(subtitleEncoding: 'GBK'));
    await h.loader.load('/s.srt', resumeKey: 'ep1.mkv');
    await h.loader.reloadWithEncoding(null);
    expect(h.prefs.forKey('ep1.mkv'), isNull);
    expect(h.transcoder.calls.last.$3, isNull);
  });

  test('reload with nothing active is a no-op', () async {
    final h = _H();
    await h.loader.reloadWithEncoding('GBK');
    expect(h.engine.externalSubtitles, isEmpty);
    expect(h.prefs.forKey('x'), isNull);
  });

  test('clear forgets the active subtitle', () async {
    final h = _H();
    await h.loader.load('/s.srt', resumeKey: 'ep1.mkv');
    h.loader.clear();
    expect(h.active, isNull);
  });
}
