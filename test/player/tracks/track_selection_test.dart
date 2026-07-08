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
    expect(d.subtitleBackgroundColor, 0x00000000);

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

  group('looksForced', () {
    test('matches forced/forzado in title or language', () {
      expect(looksForced(_MediaTrack(id: '1', title: 'Forzado')), true);
      expect(looksForced(_MediaTrack(id: '2', title: 'Forced (SDH)')), true);
      expect(looksForced(_MediaTrack(id: '3', language: 'spa', title: 'Español')), false);
      expect(looksForced(_MediaTrack(id: '4', title: 'English')), false);
    });
  });

  group('forced subtitle handling', () {
    test('selectSubtitleTrack skips a forced default in favor of a full track', () {
      final tracks = [
        _MediaTrack(id: 'f', title: 'forzado', language: 'spa', isDefault: true),
        _MediaTrack(id: 's', title: 'Español', language: 'spa'),
        _MediaTrack(id: 'e', title: 'English', language: 'eng'),
      ];
      final pick = selectSubtitleTrack(
          tracks: tracks, enabledByDefault: true, preferredLanguage: null);
      expect(pick?.id, 's');
    });

    test('preferredLanguage is honored, preferring non-forced within it', () {
      final tracks = [
        _MediaTrack(id: 'ef', title: 'English Forced', language: 'eng'),
        _MediaTrack(id: 'e', title: 'English', language: 'eng'),
        _MediaTrack(id: 's', title: 'Español', language: 'spa'),
      ];
      final pick = selectSubtitleTrack(
          tracks: tracks, enabledByDefault: true, preferredLanguage: 'eng');
      expect(pick?.id, 'e');
    });

    test('all-forced falls back to the first track (better than nothing)', () {
      final tracks = [
        _MediaTrack(id: 'f1', title: 'forzado'),
        _MediaTrack(id: 'f2', title: 'forced'),
      ];
      final pick = selectSubtitleTrack(
          tracks: tracks, enabledByDefault: true, preferredLanguage: null);
      expect(pick?.id, 'f1');
    });
  });
}

/// Helper to create MediaTrack with fewer required args for testing
MediaTrack _MediaTrack({
  required String id,
  String? title,
  String? language,
  bool isDefault = false,
}) =>
    MediaTrack(
      id: id,
      title: title,
      language: language,
      isDefault: isDefault,
    );
