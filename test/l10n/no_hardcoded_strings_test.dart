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
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// File → count of hardcoded-looking string literals, measured 2026-09-04
/// when wave 0 (foundation) landed. See the file header for what this means
/// and does not mean.
const Map<String, int> _baseline = {
  // Wave 2 (2026-09-04) localized every lib/ui/player/** file; their entries
  // are gone (0 is the default via `_baseline[rel] ?? 0`). Do not re-add one
  // to make room for new hardcoded copy there.
  'lib/ui/settings/sections/about_section.dart': 16,
  'lib/ui/settings/sections/advanced_playback_section.dart': 23,
  'lib/ui/settings/sections/backup_section.dart': 14,
  'lib/ui/settings/sections/error_log_section.dart': 7,
  'lib/ui/settings/sections/general_section.dart': 18,
  'lib/ui/settings/sections/hidden_folders_section.dart': 4,
  'lib/ui/settings/sections/interface_section.dart': 18,
  'lib/ui/settings/sections/playback_gestures_section.dart': 35,
  'lib/ui/settings/settings_screen.dart': 21,
  'lib/ui/settings/widgets/color_picker_sheet.dart': 6,
  'lib/ui/settings/widgets/setting_speed_list.dart': 3,
  'lib/ui/update/update_dialog.dart': 24,
  'lib/ui/vault/vault_gate.dart': 7,
  'lib/ui/vault/vault_screen.dart': 5,
  'lib/ui/vault/widgets/vault_bottom_bar.dart': 8,
  'lib/ui/widgets/failure_snack_bar.dart': 1,
};

final _stringLiteral = RegExp(r"'((?:[^'\\]|\\.)*)'");

// Proper nouns that read as "hardcoded UI text" by the heuristic below but
// are never translated. 'Audio' is here too, deliberately: the Sub|Audio
// track-sync-target chip labels (track_sync_hud.dart) are short technical
// track-kind labels, not sentences — same call as leaving 'Sub' unlocalized
// (it's under the length-4 floor below so it never needed whitelisting).
const _properNouns = {
  'Kivo', 'Vault', 'Android', 'Hive', 'GitHub', 'MediaStore', 'Audio',
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
