import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';

void main() {
  test('round-trips a delay and a subtitle path', () async {
    final s = InMemorySubtitlePrefsStore();
    await s.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: 500, subtitlePath: '/subs/ep1.srt'));
    expect(s.forKey('ep1.mkv')!.delayMs, 500);
    expect(s.forKey('ep1.mkv')!.subtitlePath, '/subs/ep1.srt');
  });

  test('an unknown key reads as null, not as an empty record', () {
    expect(InMemorySubtitlePrefsStore().forKey('nope.mkv'), isNull);
  });

  test('storing an empty record deletes the key instead of keeping junk', () async {
    final s = InMemorySubtitlePrefsStore();
    await s.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: 500));
    await s.put('ep1.mkv', const VideoSubtitlePrefs());
    expect(s.forKey('ep1.mkv'), isNull);
  });

  test('rename carries the record to the new key', () async {
    final s = InMemorySubtitlePrefsStore();
    await s.put('old.mkv', const VideoSubtitlePrefs(delayMs: 300));
    await s.rename('old.mkv', 'new.mkv');
    expect(s.forKey('old.mkv'), isNull);
    expect(s.forKey('new.mkv')!.delayMs, 300);
  });

  test('renaming a key with nothing stored is a no-op, not a crash', () async {
    final s = InMemorySubtitlePrefsStore();
    await s.rename('ghost.mkv', 'new.mkv');
    expect(s.forKey('new.mkv'), isNull);
  });

  test('copyWith can clear the subtitle path', () {
    const p = VideoSubtitlePrefs(delayMs: 100, subtitlePath: '/a.srt');
    expect(p.copyWith(subtitlePath: null).subtitlePath, isNull);
    expect(p.copyWith(delayMs: 200).subtitlePath, '/a.srt');
  });
}
