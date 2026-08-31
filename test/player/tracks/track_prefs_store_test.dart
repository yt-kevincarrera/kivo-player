import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';

void main() {
  test('round-trips a delay and a subtitle path', () async {
    final s = InMemoryTrackPrefsStore();
    await s.put('ep1.mkv', const VideoTrackPrefs(subtitleDelayMs: 500, subtitlePath: '/subs/ep1.srt'));
    expect(s.forKey('ep1.mkv')!.subtitleDelayMs, 500);
    expect(s.forKey('ep1.mkv')!.subtitlePath, '/subs/ep1.srt');
  });

  test('an unknown key reads as null, not as an empty record', () {
    expect(InMemoryTrackPrefsStore().forKey('nope.mkv'), isNull);
  });

  test('storing an empty record deletes the key instead of keeping junk', () async {
    final s = InMemoryTrackPrefsStore();
    await s.put('ep1.mkv', const VideoTrackPrefs(subtitleDelayMs: 500));
    await s.put('ep1.mkv', const VideoTrackPrefs());
    expect(s.forKey('ep1.mkv'), isNull);
  });

  test('rename carries the record to the new key', () async {
    final s = InMemoryTrackPrefsStore();
    await s.put('old.mkv', const VideoTrackPrefs(subtitleDelayMs: 300));
    await s.rename('old.mkv', 'new.mkv');
    expect(s.forKey('old.mkv'), isNull);
    expect(s.forKey('new.mkv')!.subtitleDelayMs, 300);
  });

  test('renaming a key with nothing stored is a no-op, not a crash', () async {
    final s = InMemoryTrackPrefsStore();
    await s.rename('ghost.mkv', 'new.mkv');
    expect(s.forKey('new.mkv'), isNull);
  });

  test('copyWith can clear the subtitle path', () {
    const p = VideoTrackPrefs(subtitleDelayMs: 100, subtitlePath: '/a.srt');
    expect(p.copyWith(subtitlePath: null).subtitlePath, isNull);
    expect(p.copyWith(subtitleDelayMs: 200).subtitlePath, '/a.srt');
  });
  test('the audio offset round-trips independently of the subtitle one', () async {
    final s = InMemoryTrackPrefsStore();
    await s.put('ep1.mkv',
        const VideoTrackPrefs(subtitleDelayMs: 500, audioDelayMs: -250));
    expect(s.forKey('ep1.mkv')!.subtitleDelayMs, 500);
    expect(s.forKey('ep1.mkv')!.audioDelayMs, -250);
  });

  test('a record holding only an audio offset is not empty', () async {
    final s = InMemoryTrackPrefsStore();
    await s.put('ep1.mkv', const VideoTrackPrefs(audioDelayMs: 200));
    expect(s.forKey('ep1.mkv')!.audioDelayMs, 200);
  });

  test('copyWith on one offset leaves the other alone', () {
    const p = VideoTrackPrefs(
        subtitleDelayMs: 100, audioDelayMs: 200, subtitlePath: '/a.srt');
    expect(p.copyWith(audioDelayMs: 300).subtitleDelayMs, 100);
    expect(p.copyWith(subtitleDelayMs: 50).audioDelayMs, 200);
    expect(p.copyWith(audioDelayMs: 300).subtitlePath, '/a.srt');
  });

  // Records written by 1.6.x have no audio key at all. They must still load,
  // with the audio offset simply absent — not throw, not lose the subtitle one.
  test('a record from before audio delay existed still loads', () {
    final p = VideoTrackPrefs.fromMap({'d': 400, 'p': '/old.srt'});
    expect(p.subtitleDelayMs, 400);
    expect(p.subtitlePath, '/old.srt');
    expect(p.audioDelayMs, 0);
  });

}
