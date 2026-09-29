import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';

void main() {
  test('decoder and encoding round-trip through toMap/fromMap', () {
    const p = VideoTrackPrefs(decoder: 'sw', subtitleEncoding: 'windows-1251');
    final back = VideoTrackPrefs.fromMap(p.toMap());
    expect(back.decoder, 'sw');
    expect(back.subtitleEncoding, 'windows-1251');
  });

  test('a record holding only a decoder override is not empty', () {
    expect(const VideoTrackPrefs(decoder: 'hw').isEmpty, isFalse);
    expect(const VideoTrackPrefs(subtitleEncoding: 'GBK').isEmpty, isFalse);
  });

  test('copyWith can clear each of them without touching the rest', () {
    const p = VideoTrackPrefs(
        subtitleDelayMs: 200, decoder: 'sw', subtitleEncoding: 'Big5');
    final noDecoder = p.copyWith(decoder: null);
    expect(noDecoder.decoder, isNull);
    expect(noDecoder.subtitleEncoding, 'Big5');
    expect(noDecoder.subtitleDelayMs, 200);
    final noEncoding = p.copyWith(subtitleEncoding: null);
    expect(noEncoding.subtitleEncoding, isNull);
    expect(noEncoding.decoder, 'sw');
  });

  test('a record from before these fields existed follows the defaults', () {
    final back = VideoTrackPrefs.fromMap({'d': 100, 'a': 0, 'p': null});
    expect(back.decoder, isNull);
    expect(back.subtitleEncoding, isNull);
  });

  test('the stored map stays the old shape when neither is set', () {
    // Backups written by this version must stay readable by the previous one.
    expect(const VideoTrackPrefs(subtitleDelayMs: 5).toMap().keys,
        unorderedEquals(['d', 'a', 'p']));
  });

  test('the store keeps a decoder-only record instead of deleting it', () async {
    final s = InMemoryTrackPrefsStore();
    await s.put('ep1.mkv', const VideoTrackPrefs(decoder: 'sw'));
    expect(s.forKey('ep1.mkv')!.decoder, 'sw');
  });
}
