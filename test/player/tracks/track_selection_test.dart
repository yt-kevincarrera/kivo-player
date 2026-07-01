import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/tracks/track_selection.dart';

const _en = MediaTrack(id: '1', title: 'English', language: 'en');
const _es = MediaTrack(id: '2', title: 'Español', language: 'es', isDefault: true);
const _fr = MediaTrack(id: '3', title: 'Français', language: 'fr');

void main() {
  test('KivoSettings subtitle/audio fields default correctly and round-trip', () {
    final d = KivoSettings.defaults();
    expect(d.subtitlesEnabledByDefault, true);
    expect(d.preferredSubtitleLanguage, isNull);
    expect(d.preferredAudioLanguage, isNull);
    expect(d.subtitleFontSize, 26.0);
    expect(d.subtitleTextColor, 0xFFFFFFFF);
    expect(d.subtitleBackgroundColor, 0xB3000000);

    final m = d
        .copyWith(
          subtitlesEnabledByDefault: false,
          preferredSubtitleLanguage: 'es',
          subtitleFontSize: 32.0,
        )
        .toMap();
    final back = KivoSettings.fromMap(m);
    expect(back.subtitlesEnabledByDefault, false);
    expect(back.preferredSubtitleLanguage, 'es');
    expect(back.subtitleFontSize, 32.0);
  });

  group('selectSubtitleTrack', () {
    test('returns null when disabled by default', () {
      expect(
        selectSubtitleTrack(tracks: [_en, _es], enabledByDefault: false, preferredLanguage: null),
        isNull,
      );
    });
    test('returns null when there are no tracks', () {
      expect(
        selectSubtitleTrack(tracks: const [], enabledByDefault: true, preferredLanguage: 'en'),
        isNull,
      );
    });
    test('prefers a track matching the preferred language', () {
      expect(
        selectSubtitleTrack(tracks: [_en, _es, _fr], enabledByDefault: true, preferredLanguage: 'fr'),
        _fr,
      );
    });
    test('falls back to the container default track when no language match', () {
      expect(
        selectSubtitleTrack(tracks: [_en, _es, _fr], enabledByDefault: true, preferredLanguage: 'de'),
        _es,
      );
    });
    test('falls back to the first track when nothing is marked default and no language match', () {
      expect(
        selectSubtitleTrack(tracks: [_en, _fr], enabledByDefault: true, preferredLanguage: 'de'),
        _en,
      );
    });
    test('shows a subtitle by default (enabled, no preference yet) via the default/first track', () {
      expect(
        selectSubtitleTrack(tracks: [_en, _es], enabledByDefault: true, preferredLanguage: null),
        _es, // _es is isDefault: true
      );
    });
  });

  group('selectAudioTrack', () {
    test('never returns null when tracks exist, even with no language match', () {
      expect(
        selectAudioTrack(tracks: [_en, _fr], preferredLanguage: 'de'),
        _en,
      );
    });
    test('prefers a track matching the preferred language', () {
      expect(
        selectAudioTrack(tracks: [_en, _es, _fr], preferredLanguage: 'es'),
        _es,
      );
    });
  });

  group('languageFromFilename', () {
    test('extracts a 2-letter code before the extension', () {
      expect(languageFromFilename('Movie.en.srt'), 'en');
    });
    test('extracts a 3-letter code before the extension', () {
      expect(languageFromFilename('Movie.spa.srt'), 'spa');
    });
    test('returns null when there is no language segment', () {
      expect(languageFromFilename('Movie.srt'), isNull);
    });
    test('returns null when the segment before the extension is not a short alpha code', () {
      expect(languageFromFilename('My.Movie.2024.srt'), isNull);
    });
  });
}
