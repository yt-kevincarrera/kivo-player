// A ratchet, not a gate: `lib/ui` is still almost entirely hardcoded Spanish
// (see docs/superpowers/specs/2026-09-04-kivo-i18n-design.md §6 — waves 1-5
// localize it screen by screen). This test cannot start at zero. Instead it
// pins today's count per file as a baseline and fails only on a REGRESSION —
// a file whose hardcoded-string count goes UP. As each wave moves a file's
// strings into the ARB, lower that file's entry (ideally to 0); never raise
// one to make room for new hardcoded copy.
//
// Heuristic: a single-quoted string literal that starts with an uppercase
// letter or ¿/¡ and is at least 4 characters long "looks like" user-facing
// text (as opposed to a lowercase enum-ish value like 'auto' or a lowercase
// import path). It is deliberately approximate — see _isWhitelisted below for
// the proper-noun exceptions — because it only needs to be *consistent*
// between generations of the baseline, not perfectly accurate.
//
// Scope note: this walk is `lib/ui` only (per the i18n design doc §5) — it
// does not reach `lib/core`, `lib/player`, `lib/platform`, `lib/app.dart` or
// `lib/main.dart`. Wave 4 swept those by hand (`grep "'[A-ZÁÉÍÓÚÑ¿¡]"`) and
// found nothing left to localize except what this wave already moved to the
// ARB (KV-nnn catalog messages via `failureMessage`, the vault/biometric
// strings, the two `BackupFile` exception messages). Everything else that
// matched the grep is intentionally NOT user-facing text and was left as-is:
//   - `debugPrint('Foo.bar failed: $e')` developer logs — present in
//     lib/core/errors/error_log.dart, lib/core/update/update_checker.dart,
//     lib/player/audio/equalizer_controller.dart,
//     lib/player/capture/frame_capture_controller.dart,
//     lib/player/tracks/subtitle_importer.dart,
//     lib/player/tracks/track_delay_controller.dart,
//     lib/platform/android/android_image_saver.dart,
//     lib/platform/android/local_auth_biometric.dart,
//     lib/player/engine/media_kit_engine.dart.
//   - `lib/core/icons/kivo_icons.dart`'s SVG path-data strings (e.g.
//     `'C9 18.5 6 16.5 3 12 Z" ...'`) — icon geometry, not text.
//   - `lib/core/update/release_notes.dart`'s `'Full Changelog:'` — matches
//     GitHub's own English release-notes boilerplate to strip it; the design
//     doc explicitly keeps release-note bodies un-localized (§4, §7).
//   - `'Kivo'` fallbacks (lib/app.dart's MaterialApp.title,
//     lib/core/format.dart, lib/player/background/background_playback.dart)
//     — the whitelisted proper noun, not a sentence.
//   - single-character `'v'`/`'V'` version-prefix checks in
//     lib/core/update/update_checker.dart and
//     lib/core/update/version_compare.dart — below the heuristic's own
//     4-character floor, not sentences either way.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// File → count of hardcoded-looking string literals, measured 2026-09-04
/// when wave 0 (foundation) landed. See the file header for what this means
/// and does not mean.
///
/// Wave 2 (2026-09-04) localized every lib/ui/player/** file; wave 3 did the
/// same for lib/ui/settings/** and lib/ui/update/**; wave 4 finished the
/// last four entries (vault_gate.dart, vault_screen.dart,
/// vault_bottom_bar.dart, failure_snack_bar.dart) — the baseline is now
/// empty. Do not add an entry back to make room for new hardcoded copy;
/// localize it instead.
const Map<String, int> _baseline = {};

final _stringLiteral = RegExp(r"'((?:[^'\\]|\\.)*)'");

// Proper nouns that read as "hardcoded UI text" by the heuristic below but
// are never translated. 'Audio' is here too, deliberately: the Sub|Audio
// track-sync-target chip labels (track_sync_hud.dart) are short technical
// track-kind labels, not sentences — same call as leaving 'Sub' unlocalized
// (it's under the length-4 floor below so it never needed whitelisting).
// 'API' joins it for the same reason: "Kivo {version} · Android API {sdk}"
// in error_log_section.dart's technical detail dump is proper nouns, a
// version number and an SDK level, not a sentence to translate.
const _properNouns = {
  'Kivo', 'Vault', 'Android', 'Hive', 'GitHub', 'MediaStore', 'Audio', 'API',
};
final _kvCode = RegExp(r'KV-\d+');
final _wordSplit = RegExp(r'[^A-Za-zÁÉÍÓÚÑÜáéíóúñü]+');

bool _looksLikeUiText(String s) {
  if (s.length < 4) return false;
  final cp = s.runes.first;
  if (cp == 0xBF || cp == 0xA1) return true; // ¿ ¡
  // Uppercase ASCII, or Latin-1 uppercase (Á É Í Ó Ú Ñ Ü and friends).
  return (cp >= 0x41 && cp <= 0x5A) || (cp >= 0xC0 && cp <= 0xDE && cp != 0xD7);
}

/// True when every "word" in [s] (once KV-nnn codes are stripped) is one of
/// the whitelisted proper nouns — e.g. "Kivo", "GitHub", "KV-014" — so a
/// literal like "Carpeta de Vault" (real text, containing a proper noun) is
/// still counted, but a bare "Vault" or "KV-014" is not.
bool _isWhitelisted(String s) {
  final withoutCodes = s.replaceAll(_kvCode, '');
  final words = withoutCodes.split(_wordSplit).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  return words.every(_properNouns.contains);
}

int _hardcodedCount(String content) {
  var n = 0;
  for (final m in _stringLiteral.allMatches(content)) {
    final s = m.group(1)!;
    if (!_looksLikeUiText(s)) continue;
    if (_isWhitelisted(s)) continue;
    n++;
  }
  return n;
}

void main() {
  test('lib/ui hardcoded-string count never regresses past its baseline', () {
    final dir = Directory('lib/ui');
    expect(dir.existsSync(), isTrue, reason: 'expected to run from the repo root');

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    final regressions = <String>[];
    final current = <String, int>{};
    for (final f in files) {
      final rel = f.path.replaceAll('\\', '/');
      final count = _hardcodedCount(f.readAsStringSync());
      if (count == 0) continue;
      current[rel] = count;
      final allowed = _baseline[rel] ?? 0;
      if (count > allowed) {
        regressions.add('$rel: $count hardcoded literal(s), baseline allows $allowed');
      }
    }

    expect(
      regressions,
      isEmpty,
      reason: 'New hardcoded UI strings crept into lib/ui. Localize them via '
          'the ARB (lib/l10n/app_es.arb + app_en.arb) and context.l10n instead '
          'of adding to the baseline:\n${regressions.join('\n')}',
    );
  });

  test('baseline has no stale entries for files that no longer exist', () {
    for (final path in _baseline.keys) {
      expect(File(path).existsSync(), isTrue, reason: '$path is in the baseline but no longer exists');
    }
  });
}
