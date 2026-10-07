import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/player/decoder/decoder_mode.dart';
import 'package:kivo_player/ui/settings/search/settings_search.dart';
import '../../helpers/pump_app.dart';

final _es = l10nFor(const Locale('es'));
final _en = l10nFor(const Locale('en'));
final _d = KivoSettings.defaults();

List<String?> _ids(List<SettingsSearchHit> hits) => [for (final h in hits) h.entry.id];

void main() {
  group('foldForSearch', () {
    test('lower-cases and strips accents', () {
      expect(foldForSearch('Subtítulos Ñandú'), 'subtitulos nandu');
    });

    test('keeps the length so match offsets map back to the original', () {
      for (final s in ['Ecualizador', 'Acción', 'İstanbul', 'Háptica en gestos']) {
        expect(foldForSearch(s).length, s.length, reason: s);
      }
    });
  });

  group('searchSettings', () {
    test('an empty or blank query returns nothing', () {
      expect(searchSettings('', _es, _d), isEmpty);
      expect(searchSettings('   ', _es, _d), isEmpty);
    });

    test('matches without accents', () {
      final hits = searchSettings('subtitulos', _es, _d);
      expect(_ids(hits), contains(SettingIds.subtitlesDefault));
      expect(_ids(hits), contains(SettingIds.preferredSubtitleLang));
    });

    test('every word must match, in any field', () {
      // «Idioma» (General) has no «audio» anywhere; the subtitle language
      // matches it only through its group, «Subtítulos y audio».
      final hits = searchSettings('idioma audio', _es, _d);
      expect(_ids(hits), isNot(contains(SettingIds.language)));
      expect(_ids(hits), contains(SettingIds.preferredSubtitleLang));
    });

    test('all words in the title beat a match that leans on the path', () {
      final hits = searchSettings('idioma audio', _es, _d);
      expect(hits.first.entry.id, SettingIds.preferredAudioLang);
    });

    test('synonyms find a setting whose visible text does not say it', () {
      expect(_ids(searchSettings('modo oscuro', _es, _d)), contains(SettingIds.theme));
      expect(_ids(searchSettings('dark mode', _en, _d)), contains(SettingIds.theme));
      expect(_ids(searchSettings('ventana flotante', _es, _d)), contains(SettingIds.pipAutoOnHome));
    });

    test('a title that starts with the query ranks above one that only contains it', () {
      // «Modo noche» starts with «modo»; «Modo incógnito» too; «Decodificador
      // por defecto» doesn't mention it in the title at all.
      final hits = searchSettings('modo noche', _es, _d);
      expect(hits.first.entry.id, SettingIds.nightMode);
    });

    test('a setting is found through its page name', () {
      final hits = searchSettings('ecualizador', _es, _d);
      // The page itself first (title starts with it), then its rows.
      expect(hits.first.entry.page, SettingsPage.equalizer);
      expect(hits.first.entry.id, isNull);
      expect(_ids(hits), contains(SettingIds.eqPreamp));
    });

    test('the path reads «Page › Group»', () {
      final hit = searchSettings('haptica', _es, _d).firstWhere((h) => h.entry.id == SettingIds.haptics);
      expect(hit.path, '${_es.settingsGeneralTitle} › ${_es.settingsGeneralGroupInteraction}');
    });

    test('title matches are reported as ranges of the original title', () {
      final hit = searchSettings('acento', _es, _d).firstWhere((h) => h.entry.id == SettingIds.accentColor);
      final (start, end) = hit.titleMatches.single;
      expect(hit.title.substring(start, end), 'acento');
    });

    test('the Vault never shows up while its entrance is hidden', () {
      final visible = searchSettings('vault', _es, _d.copyWith(vaultEntranceHidden: false));
      expect(visible.map((h) => h.entry.page), contains(SettingsPage.vault));
      final hidden = searchSettings('vault', _es, _d.copyWith(vaultEntranceHidden: true));
      expect(hidden.map((h) => h.entry.page), isNot(contains(SettingsPage.vault)));
      final bySynonym = searchSettings('privado', _es, _d.copyWith(vaultEntranceHidden: true));
      expect(bySynonym.map((h) => h.entry.page), isNot(contains(SettingsPage.vault)));
    });

    test('works in English too', () {
      final hits = searchSettings('equalizer', _en, _d);
      expect(hits.first.entry.page, SettingsPage.equalizer);
    });
  });

  group('resolveAnchor', () {
    SettingsSearchEntry entry(String id) => settingsSearchEntries.firstWhere((e) => e.id == id);

    test('a visible setting highlights itself', () {
      expect(resolveAnchor(entry(SettingIds.haptics), _d), SettingIds.haptics);
    });

    test('a hidden setting highlights the switch that reveals it', () {
      final off = _d.copyWith(showInfoOverlay: false);
      expect(resolveAnchor(entry(SettingIds.overlayCorner), off), SettingIds.showOverlay);
      final on = _d.copyWith(showInfoOverlay: true);
      expect(resolveAnchor(entry(SettingIds.overlayCorner), on), SettingIds.overlayCorner);
    });

    test('walks the chain when the revealing switch is hidden too', () {
      final s = _d.copyWith(decoderMode: DecoderMode.hardware.id, decoderAutoFallback: false);
      expect(resolveAnchor(entry(SettingIds.decoderStallSeconds), s), SettingIds.decoderMode);
      final auto = _d.copyWith(decoderMode: DecoderMode.auto.id, decoderAutoFallback: false);
      expect(resolveAnchor(entry(SettingIds.decoderStallSeconds), auto), SettingIds.decoderAutoFallback);
    });

    test('pages have no anchor', () {
      expect(resolveAnchor(settingsSearchEntries.first, _d), isNull);
    });
  });

  test('every id is unique and every fallback points at a real entry', () {
    final ids = [for (final e in settingsSearchEntries) if (e.id != null) e.id!];
    expect(ids.toSet().length, ids.length);
    for (final e in settingsSearchEntries.where((e) => e.fallback != null)) {
      expect(ids, contains(e.fallback), reason: '${e.id} → ${e.fallback}');
    }
  });
}
